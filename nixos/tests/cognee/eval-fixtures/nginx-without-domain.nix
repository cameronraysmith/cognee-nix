# Verdict: EVAL_FAIL contains "nginx.domain must be set"
# nginx reverse proxy enabled without a domain.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
    nginx.enable = true;
  };
}
