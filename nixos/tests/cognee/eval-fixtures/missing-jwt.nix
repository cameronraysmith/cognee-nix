# Verdict: EVAL_FAIL contains "jwtSecretFile must be set"
# Service enabled and llm key supplied, but the JWT secret is omitted.
{
  services.cognee = {
    enable = true;
    llm.apiKeyFile = "/run/secrets/cognee-openai";
  };
}
