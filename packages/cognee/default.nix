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
  cbor2,
  datamodel-code-generator,
  diskcache,
  fakeredis,
  fastapi,
  fastapi-users-db-sqlalchemy,
  filetype,
  gunicorn,
  instructor,
  jinja2,
  ladybug,
  lancedb,
  langdetect,
  limits,
  litellm,
  nbformat,
  networkx,
  numpy,
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
  starlette,
  structlog,
  tenacity,
  tiktoken,
  typing-extensions,
  urllib3,
  uvicorn,
  websockets,

  # optional-dependencies
  apscheduler,
  asyncpg,
  beautifulsoup4,
  chromadb,
  fastmcp,
  httpx,
  lxml,
  mcp,
  neo4j,
  nltk,
  pgvector,
  playwright,
  protego,
  psycopg2,
  psycopg2-binary,
  pypika,
  unstructured,
}:

buildPythonPackage (finalAttrs: {
  pname = "cognee";
  version = "1.1.2";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "topoteretes";
    repo = "cognee";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ef908AH6QvBLvMxR+aRy4cgK1HIpqchCquQSSJ24AWk=";
  };

  build-system = [ hatchling ];

  pythonRelaxDeps = [
    "ladybug"
    "limits"
    "pylance"
    "rdflib"
    "websockets"
  ];

  dependencies = [
    aiofiles
    aiohttp
    cryptography
    aiolimiter
    aiosqlite
    alembic
    cbor2
    datamodel-code-generator
    diskcache
    fakeredis
    fastapi
    fastapi-users-db-sqlalchemy
    filetype
    gunicorn
    instructor
    jinja2
    ladybug
    lancedb
    langdetect
    limits
    litellm
    nbformat
    networkx
    numpy
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
    starlette
    structlog
    tenacity
    tiktoken
    typing-extensions
    urllib3
    uvicorn
    websockets
  ];

  optional-dependencies = {
    chromadb = [
      chromadb
      pypika
    ];
    docs = [
      lxml
      nltk
      unstructured
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
    postgres-binary = [
      asyncpg
      pgvector
      psycopg2-binary
    ];
    scraping = [
      apscheduler
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
