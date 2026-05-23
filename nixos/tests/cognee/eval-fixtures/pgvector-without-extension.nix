# Verdict: EVAL_FAIL contains "enablePgvector must be true"
# pgvector chosen as vector backend but the PostgreSQL extension is not enabled.
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
    vectorStore.backend = "pgvector";
    database.enablePgvector = false;
  };
}
