# Verdict: EVAL_OK
# Minimal valid configuration: enable + jwt + llm.apiKeyFile with default openai provider.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
  };
}
