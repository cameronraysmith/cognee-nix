# Verdict: EVAL_OK
# Full stack: API + MCP + frontend + nginx with public domain.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
    mcp.enable = true;
    frontend.enable = true;
    nginx = {
      enable = true;
      domain = "cognee.example";
    };
  };
}
