{
  flake.overlays.default = _final: prev: {
    pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
      (python-final: python-prev: {
        fastapi-users = python-final.callPackage ../packages/fastapi-users { };
        fastapi-users-db-sqlalchemy = python-final.callPackage ../packages/fastapi-users-db-sqlalchemy { };
        ladybug = python-final.callPackage ../packages/ladybug { };
        # Preserve the legacy attribute name from nixpkgs by aliasing it to the
        # new ladybug derivation. Anything that still consumes
        # `python313Packages.real-ladybug` (including this overlay's own cognee
        # consumers if they haven't been migrated yet) gets the v0.16.0 build
        # whose installed module is `ladybug`.
        real-ladybug = python-final.ladybug;
        cognee = python-final.callPackage ../packages/cognee { };
        cognee-mcp = python-final.callPackage ../packages/cognee-mcp { };
      })
    ];
  };
}
