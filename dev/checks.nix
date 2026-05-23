{
  perSystem =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      packageChecks = lib.mapAttrs' (name: pkg: lib.nameValuePair "package-${name}" pkg) config.packages;

      cogneeModulePath = ../nixos/modules/cognee.nix;
      cogneeFixturesDir = ../nixos/tests/cognee/eval-fixtures;

      # Evaluate the cognee module inside a full NixOS module system so that
      # ambient options like `networking.firewall`, `users`, `systemd.services`,
      # `services.postgresql`, and `assertions` resolve through their canonical
      # declarations rather than being re-declared piecemeal here.
      cogneeOverlay = (import ../overlays/flake-module.nix).flake.overlays.default;

      # Shared harness applied to every fixture composition: a stub host
      # platform so eval works on darwin, the cognee overlay so the package
      # set surfaces the cognee derivations, and ACME terms acceptance so the
      # ambient nginx-with-TLS path does not generate assertion noise that
      # masks the cognee-owned assertions under test.
      cogneeBaseModule =
        { lib, ... }:
        {
          boot.isContainer = true;
          system.stateVersion = lib.trivial.release;
          nixpkgs.overlays = [ cogneeOverlay ];
          nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
          security.acme.acceptTerms = true;
          security.acme.defaults.email = "admin@example.invalid";
        };

      evalCognee =
        extraModule:
        import (pkgs.path + "/nixos/lib/eval-config.nix") {
          system = null;
          modules = [
            (import cogneeModulePath)
            cogneeBaseModule
            extraModule
          ];
        };

      cogneeNixos = evalCognee {
        services.cognee = {
          enable = true;
          auth.jwtSecretFile = "/run/secrets/cognee-jwt";
          llm.apiKeyFile = "/run/secrets/cognee-openai";
        };
      };

      # Options snapshot reuses the full NixOS evaluation and filters down to
      # the services.cognee subtree so ambient options stay resolvable.
      optionsDoc = pkgs.nixosOptionsDoc {
        options = cogneeNixos.options.services.cognee;
        transformOptions =
          opt:
          opt
          // {
            declarations = map (_: "nixos/modules/cognee.nix") opt.declarations;
          };
      };

      # Tier 1.3 — Assertion coverage. Each fixture file under
      # nixos/tests/cognee/eval-fixtures/ is paired with a verdict. EVAL_OK
      # fixtures must produce no failed assertions from the cognee module;
      # EVAL_FAIL fixtures must surface a failed assertion whose message
      # contains the named substring. Ambient NixOS assertions (e.g. from
      # services.nginx or security.acme) are filtered out so the check only
      # exercises the cognee-owned assertion surface.
      assertionFixtures = [
        {
          name = "minimal-ok";
          expect = "ok";
        }
        {
          name = "missing-jwt";
          expect = "fail";
          match = "jwtSecretFile must be set";
        }
        {
          name = "missing-llm-key";
          expect = "fail";
          match = "llm.apiKeyFile must be set";
        }
        {
          name = "ollama-no-key-ok";
          expect = "ok";
        }
        {
          name = "nginx-without-domain";
          expect = "fail";
          match = "nginx.domain must be set";
        }
        {
          name = "pgvector-without-extension";
          expect = "fail";
          match = "enablePgvector must be true";
        }
        {
          name = "pgvector-ok";
          expect = "ok";
        }
        {
          name = "mcp-ok";
          expect = "ok";
        }
        {
          name = "frontend-ok";
          expect = "ok";
        }
        {
          name = "full-stack-ok";
          expect = "ok";
        }
      ];

      # Restrict to assertions owned by the cognee module: every cognee
      # assertion message begins with `services.cognee` per the module body.
      isCogneeAssertion = msg: lib.hasPrefix "services.cognee" msg;

      fixtureMessages =
        fixtureName:
        let
          eval = evalCognee (import (cogneeFixturesDir + "/${fixtureName}.nix"));
          failed = builtins.filter (a: !a.assertion) eval.config.assertions;
          messages = map (a: a.message) failed;
        in
        builtins.filter isCogneeAssertion messages;

      evaluateFixture =
        { name, expect, ... }@spec:
        let
          messages = fixtureMessages name;
          messageList = builtins.concatStringsSep " | " messages;
          ok =
            if expect == "ok" then
              messages == [ ]
            else if expect == "fail" then
              builtins.any (m: lib.hasInfix spec.match m) messages
            else
              throw "unknown verdict: ${expect}";
          verdict = if ok then "PASS" else "FAIL";
          detail =
            if expect == "ok" then
              "expected no cognee assertions; got [${messageList}]"
            else
              "expected match '${spec.match}'; got [${messageList}]";
        in
        {
          inherit
            name
            expect
            ok
            verdict
            detail
            ;
          line = "${verdict} ${name} (${expect}) — ${detail}";
        };

      fixtureResults = map evaluateFixture assertionFixtures;
      allFixturesPassed = builtins.all (r: r.ok) fixtureResults;
      fixtureReport = builtins.concatStringsSep "\n" (map (r: r.line) fixtureResults);

      # Tier 1.4 — Systemd unit shape audit. Evaluate the full-stack fixture,
      # then assert structural properties on the rendered cognee.service unit
      # text plus the module-source body that feeds writeShellScript. The
      # unit text covers hardening directives nixos renders into [Service].
      # The ExecStart payload (gunicorn/uvicorn entry point) is asserted
      # against the cognee module source rather than the realised script
      # because realising the script would pull the cognee python env into
      # the check closure, defeating its purpose as a pure eval-tier check.
      systemdShapeEval = evalCognee (import (cogneeFixturesDir + "/full-stack-ok.nix"));
      cogneeUnitText = systemdShapeEval.config.systemd.units."cognee.service".text;
      cogneeModuleSource = builtins.readFile cogneeModulePath;

      hasSubstring = needle: haystack: lib.hasInfix needle haystack;

      requireSubstring =
        label: needle: haystack:
        if hasSubstring needle haystack then
          "PASS require '${needle}' in ${label}"
        else
          throw "cognee-module-systemd-shape: required substring '${needle}' missing from ${label}";

      forbidSubstring =
        label: needle: haystack:
        if hasSubstring needle haystack then
          throw "cognee-module-systemd-shape: forbidden substring '${needle}' present in ${label}"
        else
          "PASS forbid '${needle}' in ${label}";

      unitChecks = [
        (requireSubstring "cognee.service" "StateDirectory=cognee" cogneeUnitText)
        (requireSubstring "cognee.service" "StateDirectoryMode=0700" cogneeUnitText)
        (requireSubstring "cognee.service" "ProtectSystem=strict" cogneeUnitText)
        (requireSubstring "cognee.service" "NoNewPrivileges=true" cogneeUnitText)
        (requireSubstring "cognee.service" "PrivateTmp=true" cogneeUnitText)
        (requireSubstring "cognee.service" "User=cognee" cogneeUnitText)
        (requireSubstring "cognee.service" "Group=cognee" cogneeUnitText)
        (requireSubstring "cognee.service" "LoadCredential=FASTAPI_USERS_JWT_SECRET:/run/secrets/cognee-jwt"
          cogneeUnitText
        )
        (requireSubstring "cognee.service" "LoadCredential=LLM_API_KEY:/run/secrets/cognee-openai"
          cogneeUnitText
        )
        (requireSubstring "cognee.service" "RestrictAddressFamilies=AF_INET" cogneeUnitText)
        (requireSubstring "cognee.service" "RestrictAddressFamilies=AF_UNIX" cogneeUnitText)
        (requireSubstring "cognee.service" "RestrictNamespaces=true" cogneeUnitText)
        (requireSubstring "cognee.service" "Restart=on-failure" cogneeUnitText)
        (forbidSubstring "cognee.service" "User=root" cogneeUnitText)
        (requireSubstring "cognee module source" "/bin/gunicorn" cogneeModuleSource)
        (requireSubstring "cognee module source" "uvicorn.workers.UvicornWorker" cogneeModuleSource)
        (requireSubstring "cognee module source" "cognee.api.client:app" cogneeModuleSource)
      ];
    in
    {
      checks = packageChecks // {
        cognee-module-eval = pkgs.runCommand "cognee-module-eval" { } ''
          pname=${cogneeNixos.config.services.cognee.package.pname}
          echo "$pname" > "$out"
          if [ "$pname" != "cognee" ]; then
            echo "package.pname mismatch: $pname" >&2
            exit 1
          fi
        '';

        cognee-module-options-snapshot = pkgs.runCommand "cognee-module-options-snapshot" { } ''
          cp ${optionsDoc.optionsCommonMark} "$out"
        '';

        cognee-module-assertions =
          pkgs.runCommand "cognee-module-assertions"
            {
              passthru = {
                inherit fixtureResults allFixturesPassed;
              };
            }
            ''
              cat > "$out" <<'REPORT'
              cognee module assertion coverage
              ================================
              ${fixtureReport}
              REPORT
              ${lib.optionalString (!allFixturesPassed) ''
                echo "one or more cognee fixtures produced an unexpected verdict; see $out" >&2
                cat "$out" >&2
                exit 1
              ''}
            '';

        cognee-module-systemd-shape =
          pkgs.runCommand "cognee-module-systemd-shape"
            {
              passthru = {
                inherit unitChecks;
              };
            }
            ''
              # Each requireSubstring/forbidSubstring helper throws at Nix
              # eval time on failure, so reaching this shell already means
              # every structural assertion held. Materialise the report.
              cat > "$out" <<'REPORT'
              cognee.service shape audit
              ==========================
              ${builtins.concatStringsSep "\n" unitChecks}
              REPORT
            '';
      };
    };
}
