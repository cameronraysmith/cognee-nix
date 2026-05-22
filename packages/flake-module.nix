{
  perSystem =
    { pkgs, ... }:
    let
      python = pkgs.python313;
      pythonPackages = python.pkgs;

      fastapi-users = pythonPackages.callPackage ./fastapi-users { };
      fastapi-users-db-sqlalchemy = pythonPackages.callPackage ./fastapi-users-db-sqlalchemy {
        inherit fastapi-users;
      };
      ladybug = pythonPackages.callPackage ./ladybug { };
      # Upstream pgvector lists postgresqlTestHook in nativeCheckInputs, but that hook
      # has badPlatforms on darwin and is forced during eval of the package's
      # nativeBuildInputs (buildPythonPackage merges check inputs in). Stub it out at
      # the callPackage layer with a no-op derivation, and disable the check phase
      # defensively (the remaining tests require a running postgres anyway).
      pgvector =
        (pythonPackages.pgvector.override {
          postgresqlTestHook = pkgs.emptyDirectory;
        }).overrideAttrs
          (_: {
            # buildPythonPackage's pytestCheckHook ignores doCheck/dontCheck; suppress
            # it explicitly. The tests require a running postgres anyway, so this is
            # the only viable path in a hermetic sandbox.
            dontUsePytestCheck = true;
          });
      cognee = pythonPackages.callPackage ./cognee {
        inherit fastapi-users-db-sqlalchemy ladybug pgvector;
      };
      cognee-mcp = pythonPackages.callPackage ./cognee-mcp {
        inherit cognee;
      };
      cognee-frontend = pkgs.callPackage ./cognee-frontend { };
    in
    {
      packages = {
        inherit
          cognee
          cognee-frontend
          cognee-mcp
          fastapi-users
          fastapi-users-db-sqlalchemy
          ladybug
          pgvector
          ;
      };
    };
}
