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
  langdetect,
  limits,
  litellm,
  nbformat,
  networkx,
  numpy,
  openai,
  pydantic,
  pydantic-settings,
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

  # Release read-only auth sessions explicitly so the connection returns to the
  # pool instead of lingering idle-in-transaction, which otherwise exhausts the
  # postgres pool under repeated API-key/auth lookups. rollback is correct and
  # idempotent here because both sites are read-only.
  patches = [
    ./patches/0001-session-rollback-get-user-db.patch
    ./patches/0002-session-rollback-get-by-token.patch
  ];

  postPatch = ''
    # The hosted SaaS 307-redirects the bare datasets collection to its trailing-slash form.
    substituteInPlace cognee/cli/api_client.py \
      --replace-fail '"/api/v1/datasets"' '"/api/v1/datasets/"'

    # nixpkgs ships structlog 26.1.0, above the upstream <26 cap. cognee imports and
    # behaves identically against 26.1.0, and no structlog surface changed in 26 is
    # used by cognee. Only the cap is dropped; the >=25.2.0 floor still applies, and
    # --replace-fail fails the build if upstream revises this constraint.
    substituteInPlace pyproject.toml \
      --replace-fail '"structlog>=25.2.0,<26"' '"structlog>=25.2.0"'
  '';

  pythonRelaxDeps = [
    # nixpkgs ships gunicorn 26.0.0, above the upstream <24 cap. gunicorn is never
    # imported on the path this package is used for: cognee-cli speaking HTTP to a
    # remote API server.
    "gunicorn"
    "limits"
    "rdflib"
    "websockets"
  ];

  # lancedb and pylance are removed rather than relaxed. nixpkgs builds rustc 1.97.0
  # against LLVM 21.1.8 while rust 1.97.0 pins LLVM 22 in src/llvm-project, and the
  # AVX-512 VNNI intrinsic signatures changed after the 21.1 branch
  # (llvm/llvm-project#155194). lance-linalg calls _mm512_dpbusd_epi32 and
  # _mm512_dpwssd_epi32 unconditionally under cfg(target_arch = "x86_64") with runtime
  # feature detection, so no cargo feature avoids the codegen and both packages fail to
  # build on x86_64-linux. Restore them once nixpkgs #524570 and #544495 land off
  # staging. cognee imports LanceDBAdapter only inside the lancedb branch of
  # create_vector_engine and has no non-test `import lance`, so the pgvector and qdrant
  # backends are unaffected; the lancedb backend is unavailable meanwhile. Upstream
  # still declares both in pyproject.toml, so the Requires-Dist lines must be stripped
  # or pythonRuntimeDepsCheckHook fails on the absent distributions.
  pythonRemoveDeps = [
    "lancedb"
    "pylance"
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
    langdetect
    limits
    litellm
    nbformat
    networkx
    numpy
    openai
    pydantic
    pydantic-settings
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
