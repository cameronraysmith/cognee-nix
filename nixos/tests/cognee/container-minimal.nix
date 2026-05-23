{ pkgs, ... }:
let
  cogneeModule = ../../modules/cognee.nix;
  cogneeOverlay = (import ../../../overlays/flake-module.nix).flake.overlays.default;

  # Stub credentials. These are inert placeholders that satisfy the module's
  # required-file assertions for jwtSecretFile and llm.apiKeyFile. The test
  # toggles MOCK_EMBEDDING so cognee never actually contacts an LLM provider.
  jwtStub = pkgs.writeText "cognee-jwt-stub" "test-jwt-secret-not-for-prod-XXXXXXXXXX";
  openaiStub = pkgs.writeText "cognee-openai-stub" "sk-test-mock-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX";
in
{
  name = "cognee-container-minimal";

  # Allow nodes/containers to extend `nixpkgs.overlays`. The test framework
  # otherwise locks the pkgs config to `node.pkgs`, which would block the
  # cognee overlay needed to surface `pkgs.python313Packages.cognee`.
  node.pkgsReadOnly = false;

  containers.machine =
    { lib, ... }:
    {
      imports = [ cogneeModule ];

      nixpkgs.overlays = [ cogneeOverlay ];

      services.cognee = {
        enable = true;

        # Embedded-only path: sqlite + lancedb + ladybug. No postgres provisioning.
        database.createLocally = false;
        settings.DB_PROVIDER = "sqlite";

        vectorStore.backend = "lancedb";
        graphStore.backend = "ladybug";

        auth.jwtSecretFile = jwtStub;
        auth.defaultUserEmail = "test@example.com";

        llm.apiKeyFile = openaiStub;

        # Hermetic settings: mock the embedding provider so startup does not
        # require network access to OpenAI, and disable telemetry so the
        # service does not attempt outbound posthog calls.
        settings.MOCK_EMBEDDING = "true";
        settings.TELEMETRY_DISABLED = "true";
      };

      system.stateVersion = lib.trivial.release;
    };

  testScript = ''
    machine.wait_for_unit("cognee.service")
    machine.wait_for_open_port(8000)
    machine.succeed("curl --fail http://127.0.0.1:8000/health")
  '';
}
