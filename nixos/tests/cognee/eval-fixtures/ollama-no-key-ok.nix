# Verdict: EVAL_OK
# Ollama provider does not require an apiKeyFile because it authenticates
# implicitly via the local LLM_ENDPOINT.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm = {
      provider = "ollama";
      endpoint = "http://localhost:11434";
    };
  };
}
