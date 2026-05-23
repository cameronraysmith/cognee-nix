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

      # Inject the locally-built cognee-frontend derivation into the eval-time
      # nixpkgs so that fixtures enabling the frontend can render their unit
      # text without the option's default (`pkgs.cognee-frontend or null`)
      # collapsing to `null`. The frontend is a Node.js package and lives in
      # the per-system flake outputs rather than the python overlay.
      cogneeFrontendOverlay = _: _: { inherit (config.packages) cognee-frontend; };

      # Shared harness applied to every fixture composition: a stub host
      # platform so eval works on darwin, the cognee overlay so the package
      # set surfaces the cognee derivations, the frontend injection overlay,
      # and ACME terms acceptance so the ambient nginx-with-TLS path does not
      # generate assertion noise that masks the cognee-owned assertions under
      # test.
      cogneeBaseModule =
        { lib, ... }:
        {
          boot.isContainer = true;
          system.stateVersion = lib.trivial.release;
          nixpkgs.overlays = [
            cogneeOverlay
            cogneeFrontendOverlay
          ];
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

      # Tier 1.4 — Systemd unit shape audit, expanded into a per-fixture
      # matrix. For each OK fixture, evaluate the full NixOS module system,
      # then assert structural properties on the rendered systemd unit
      # text(s). All assertions are forced at Nix eval time via `throw`, so
      # a derivation that builds successfully implies every substring
      # constraint held. The ExecStart payload (gunicorn/uvicorn entry
      # point) is asserted against the cognee module source rather than the
      # realised script because realising it would pull the cognee python
      # env into the check closure, defeating the purpose as a pure
      # eval-tier check.
      cogneeModuleSource = builtins.readFile cogneeModulePath;

      # Hardening directives common to every cognee-owned systemd unit
      # (cognee.service, cognee-mcp.service, cognee-frontend.service). The
      # module body merges the shared `hardening` attrset into each unit's
      # serviceConfig, so a single check function suffices.
      commonHardening = [
        "StateDirectory=cognee"
        "StateDirectoryMode=0700"
        "ProtectSystem=strict"
        "NoNewPrivileges=true"
        "PrivateTmp=true"
        "User=cognee"
        "Group=cognee"
        "RestrictAddressFamilies=AF_INET"
        "RestrictAddressFamilies=AF_UNIX"
        "RestrictNamespaces=true"
        "Restart=on-failure"
      ];

      hasSubstring = needle: haystack: lib.hasInfix needle haystack;

      requireIn =
        label: needle: haystack:
        if hasSubstring needle haystack then
          "PASS require '${needle}' in ${label}"
        else
          throw "cognee-module-shape: required substring '${needle}' missing from ${label}";

      forbidIn =
        label: needle: haystack:
        if hasSubstring needle haystack then
          throw "cognee-module-shape: forbidden substring '${needle}' present in ${label}"
        else
          "PASS forbid '${needle}' in ${label}";

      # Per-fixture shape specification. Each entry names an OK fixture and
      # declares the required/forbidden substrings within each rendered unit
      # plus optional checks against the module source.
      #
      # NOTE on `default-minimal`: the `minimal-ok` fixture leaves
      # `database.createLocally` at its default (`true`), so `DB_PROVIDER`
      # renders as `postgres` rather than `sqlite`. We assert postgres
      # accordingly. A sqlite-rendering fixture would need
      # `database.createLocally = false`, which no current fixture sets.
      shapeFixtures = {
        default-minimal = {
          fixture = "minimal-ok";
          units = {
            "cognee.service" = {
              requires = commonHardening ++ [
                "LoadCredential=FASTAPI_USERS_JWT_SECRET"
                "LoadCredential=LLM_API_KEY"
                "DB_PROVIDER=postgres"
                "VECTOR_DB_PROVIDER=lancedb"
              ];
              forbids = [
                "User=root"
                "DB_PROVIDER=sqlite"
              ];
            };
          };
        };

        postgres-pgvector = {
          fixture = "pgvector-ok";
          units = {
            "cognee.service" = {
              requires = commonHardening ++ [
                "LoadCredential=FASTAPI_USERS_JWT_SECRET"
                "DB_PROVIDER=postgres"
                "VECTOR_DB_PROVIDER=pgvector"
              ];
              forbids = [
                "User=root"
                "VECTOR_DB_PROVIDER=lancedb"
              ];
            };
          };
        };

        mcp-companion = {
          fixture = "mcp-ok";
          units = {
            "cognee.service" = {
              requires = commonHardening ++ [ "ExecStart=" ];
              forbids = [ "User=root" ];
            };
            "cognee-mcp.service" = {
              requires = [
                "/bin/cognee-mcp"
                "--transport"
                "--api-url"
                "User=cognee"
                "ProtectSystem=strict"
                "Restart=on-failure"
              ];
              forbids = [ "User=root" ];
            };
          };
        };

        frontend-companion = {
          fixture = "frontend-ok";
          units = {
            "cognee.service" = {
              requires = commonHardening;
              forbids = [ "User=root" ];
            };
            "cognee-frontend.service" = {
              requires = [
                "/bin/cognee-frontend"
                "NEXT_PUBLIC_BACKEND_API_URL"
                "User=cognee"
                "ProtectSystem=strict"
                "Restart=on-failure"
              ];
              forbids = [ "User=root" ];
            };
          };
        };

        full-stack = {
          fixture = "full-stack-ok";
          units = {
            "cognee.service" = {
              requires = commonHardening ++ [
                "DB_PROVIDER=postgres"
                "LoadCredential=FASTAPI_USERS_JWT_SECRET"
                "LoadCredential=LLM_API_KEY"
                "ExecStart="
              ];
              forbids = [ "User=root" ];
            };
            "cognee-mcp.service" = {
              requires = [
                "--api-url"
                "/bin/cognee-mcp"
              ];
              forbids = [ "User=root" ];
            };
            "cognee-frontend.service" = {
              requires = [
                "/bin/cognee-frontend"
                "NEXT_PUBLIC_BACKEND_API_URL"
              ];
              forbids = [ "User=root" ];
            };
          };
          # Module-source assertions are only meaningful once per matrix; we
          # anchor them on the full-stack entry which exercises every
          # codepath the module gates on.
          sourceRequires = [
            "/bin/gunicorn"
            "uvicorn.workers.UvicornWorker"
            "cognee.api.client:app"
          ];
        };
      };

      evalShapeFixture =
        spec:
        let
          eval = evalCognee (import (cogneeFixturesDir + "/${spec.fixture}.nix"));
          units = eval.config.systemd.units;

          checkUnit =
            unitName:
            { requires, forbids }:
            let
              text = units.${unitName}.text;
              requireLines = map (n: requireIn unitName n text) requires;
              forbidLines = map (n: forbidIn unitName n text) forbids;
            in
            requireLines ++ forbidLines;

          unitLines = lib.concatLists (
            lib.mapAttrsToList checkUnit spec.units
          );

          sourceLines = map (n: requireIn "cognee module source" n cogneeModuleSource) (
            spec.sourceRequires or [ ]
          );
        in
        unitLines ++ sourceLines;

      buildShapeCheck =
        name: spec:
        let
          lines = evalShapeFixture spec;
          report = builtins.concatStringsSep "\n" lines;
        in
        pkgs.runCommand "cognee-module-shape-${name}"
          {
            passthru = {
              inherit lines;
            };
          }
          ''
            cat > "$out" <<'REPORT'
            cognee systemd shape audit (${name}, fixture: ${spec.fixture})
            ==============================================================
            ${report}
            REPORT
          '';

      shapeMatrixChecks = lib.mapAttrs' (
        name: spec: lib.nameValuePair "cognee-module-shape-${name}" (buildShapeCheck name spec)
      ) shapeFixtures;

      # Tier 1.5 — Static lints. statix surfaces idiomatic-nix warnings;
      # deadnix surfaces unused bindings. Both run as pure derivations
      # against the module source and the eval-fixtures directory. statix
      # accepts a single TARGET per invocation, so we run it once per path.
      lintTargets = [
        cogneeModulePath
        ../nixos/tests/cognee
      ];

      lintStatixScript = lib.concatMapStringsSep "\n" (target: ''
        ${pkgs.statix}/bin/statix check ${target}
      '') lintTargets;

      lintDeadnixScript = lib.concatMapStringsSep "\n" (target: ''
        ${pkgs.deadnix}/bin/deadnix --fail ${target}
      '') lintTargets;
    in
    {
      checks = packageChecks // shapeMatrixChecks // {
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

        cognee-module-lint-statix = pkgs.runCommand "cognee-module-lint-statix" { } ''
          ${lintStatixScript}
          touch "$out"
        '';

        cognee-module-lint-deadnix = pkgs.runCommand "cognee-module-lint-deadnix" { } ''
          ${lintDeadnixScript}
          touch "$out"
        '';
      };
    };
}
