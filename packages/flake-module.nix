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
      cognee = pythonPackages.callPackage ./cognee {
        inherit fastapi-users-db-sqlalchemy ladybug;
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
          ;
      };
    };
}
