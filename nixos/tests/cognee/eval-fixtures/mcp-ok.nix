# Verdict: EVAL_OK
# Companion cognee-mcp service enabled on top of the minimal valid configuration.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
    mcp.enable = true;
  };
}
