# Verdict: EVAL_OK
# pgvector chosen as vector backend with the PostgreSQL extension enabled.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
    vectorStore.backend = "pgvector";
    database.enablePgvector = true;
  };
}
