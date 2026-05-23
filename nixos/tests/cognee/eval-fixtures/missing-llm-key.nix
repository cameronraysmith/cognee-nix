# Verdict: EVAL_FAIL contains "llm.apiKeyFile must be set"
# JWT supplied but the default openai provider has no apiKeyFile.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
  };
}
