{
  perSystem =
    {
      lib,
      pkgs,
      system,
      ...
    }:
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        cognee-container-test-minimal = pkgs.testers.runNixOSTest (
          import ./cognee/container-minimal.nix
        );
      };
    };
}
