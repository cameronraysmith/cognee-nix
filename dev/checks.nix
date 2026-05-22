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

      # Evaluate the cognee module inside a full NixOS module system so that
      # ambient options like `networking.firewall`, `users`, `systemd.services`,
      # `services.postgresql`, and `assertions` resolve through their canonical
      # declarations rather than being re-declared piecemeal here.
      cogneeOverlay = (import ../overlays/flake-module.nix).flake.overlays.default;

      cogneeNixos = import (pkgs.path + "/nixos/lib/eval-config.nix") {
        system = null;
        modules = [
          (import cogneeModulePath)
          (
            { lib, ... }:
            {
              # Stub the boot/hardware surface that NixOS expects from a system
              # closure; the cognee module touches none of it, but eval-config
              # walks the full module tree.
              boot.isContainer = true;
              system.stateVersion = lib.trivial.release;
              nixpkgs.overlays = [ cogneeOverlay ];
              # Allow eval on darwin host even though the resulting NixOS
              # config targets linux; the check only inspects option values.
              nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
              services.cognee = {
                enable = true;
                auth.jwtSecretFile = "/run/secrets/cognee-jwt";
                llm.apiKeyFile = "/run/secrets/cognee-openai";
              };
            }
          )
        ];
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

      moduleChecks = {
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
      };
    in
    {
      checks = packageChecks // moduleChecks;
    };
}
