{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  aiofiles,
  cryptography,
  aiohttp,
  aiolimiter,
  aiosqlite,
  alembic,
  diskcache,
  fakeredis,
  fastembed,
  fastapi,
  fastapi-users-db-sqlalchemy,
  filetype,
  gunicorn,
  instructor,
  jinja2,
  kuzu,
  lancedb,
  limits,
  litellm,
  mistralai,
  nbformat,
  networkx,
  numpy,
  onnxruntime,
  openai,
  pydantic,
  pydantic-settings,
  pylance,
  pympler,
  pypdf,
  python-dotenv,
  python-multipart,
  rdflib,
  sqlalchemy,
  structlog,
  tenacity,
  tiktoken,
  transformers,
  typing-extensions,
  uvicorn,
  websockets,

  # optional-dependencies
  asyncpg,
  beautifulsoup4,
  chromadb,
  fastmcp,
  httpx,
  lxml,
  mcp,
  neo4j,
  pgvector,
  playwright,
  protego,
  psycopg2,
  pypika,
}:

buildPythonPackage (finalAttrs: {
  pname = "cognee";
  version = "0.5.1";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "topoteretes";
    repo = "cognee";
    tag = "v${finalAttrs.version}";
    hash = "sha256-4s3DOvHsAHHoyivwcMX7JJNzNzueAE/qdrdd1w6HGkc=";
  };

  build-system = [ hatchling ];

  pythonRelaxDeps = [
    "fastembed"
    "fastapi-users"
    "kuzu"
    "limits"
    "onnxruntime"
    "pydantic"
    "pylance"
    "rdflib"
  ];

  dependencies = [
    aiofiles
    aiohttp
    cryptography
    aiolimiter
    aiosqlite
    alembic
    diskcache
    fakeredis
    fastembed
    fastapi
    fastapi-users-db-sqlalchemy
    filetype
    gunicorn
    instructor
    jinja2
    kuzu
    lancedb
    limits
    litellm
    mistralai
    nbformat
    networkx
    numpy
    onnxruntime
    openai
    pydantic
    pydantic-settings
    pylance
    pympler
    pypdf
    python-dotenv
    python-multipart
    rdflib
    sqlalchemy
    structlog
    tenacity
    tiktoken
    transformers
    typing-extensions
    uvicorn
    websockets
  ];

  optional-dependencies = {
    chromadb = [
      chromadb
      pypika
    ];
    mcp = [
      fastmcp
      httpx
      mcp
    ];
    neo4j = [ neo4j ];
    postgres = [
      asyncpg
      pgvector
      psycopg2
    ];
    scraping = [
      beautifulsoup4
      lxml
      playwright
      protego
    ];
  };

  # Tests require external services (databases, LLM APIs)
  doCheck = false;

  pythonImportsCheck = [ "cognee" ];

  meta = {
    changelog = "https://github.com/topoteretes/cognee/releases/tag/${finalAttrs.src.tag}";
    description = "Memory management for AI applications and AI agents";
    homepage = "https://github.com/topoteretes/cognee";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ mulatta ];
  };
})
