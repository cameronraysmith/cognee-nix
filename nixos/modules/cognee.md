# Cognee {#module-services-cognee}

Cognee is a knowledge graph and memory service built on FastAPI with pluggable
vector and graph backends. The NixOS module wires a `cognee.api.client:app`
gunicorn worker, optional local PostgreSQL (with pgvector when the vector
backend requires it), and optional companion services for `cognee-mcp` and the
`cognee-frontend` Next.js UI.

A minimal configuration enables the service with a JWT secret and an LLM API
key delivered via systemd credentials:

```nix
{
  services.cognee = {
    enable = true;
    auth.jwtSecretFile = "/run/secrets/cognee-jwt";
    llm.apiKeyFile = "/run/secrets/cognee-openai";
  };
}
```

See the option documentation for the full schema, including database,
vector-store, graph-store, MCP, frontend, and nginx integration knobs.
