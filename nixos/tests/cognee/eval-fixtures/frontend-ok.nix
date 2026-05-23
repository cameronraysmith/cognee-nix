# Verdict: EVAL_OK
# Cognee Next.js frontend enabled on top of the minimal valid configuration.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
    frontend.enable = true;
  };
}
