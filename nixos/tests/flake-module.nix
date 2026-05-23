{ inputs, ... }:
{
  # cognee-container-test-minimal is intentionally NOT under flake.checks because
  # systemd-nspawn requires kernel capabilities (pidfd_open, namespace creation,
  # immutable attrs on tmpfs) that the nix build sandbox restricts and that
  # rosetta-builder's Lima VM does not currently grant. Run manually via
  #   nix build .#nixosTests.x86_64-linux.cognee-container-test-minimal
  # on a host with relaxed sandboxing (e.g. buildbot-nix on magnetite, or any
  # bare-metal NixOS host with sandbox = false in nix.conf).
  flake.nixosTests = {
    x86_64-linux = {
      cognee-container-test-minimal =
        let
          pkgs = import inputs.nixpkgs {
            system = "x86_64-linux";
            overlays = [ (import ../../overlays/flake-module.nix).flake.overlays.default ];
          };
        in
        pkgs.testers.runNixOSTest (import ./cognee/container-minimal.nix);
    };
  };
}
