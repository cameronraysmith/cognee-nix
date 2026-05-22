{
  lib,
  buildPythonPackage,
  fetchFromGitHub,

  # build-system
  hatchling,

  # dependencies
  cognee,
  httpx,
  mcp,
}:

buildPythonPackage (finalAttrs: {
  pname = "cognee-mcp";
  version = "1.1.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "topoteretes";
    repo = "cognee";
    tag = "v${finalAttrs.version}";
    hash = "sha256-d9itqlCbEBJZilCJsBldUkg1Uy9GCor1cCemazLTJmo=";
  };

  sourceRoot = "source/cognee-mcp";

  build-system = [ hatchling ];

  pythonRelaxDeps = [ "cognee" ];
  pythonRemoveDeps = [ "uv" ];

  dependencies = [
    cognee
    httpx
    mcp
  ]
  ++ cognee.optional-dependencies.docs
  ++ cognee.optional-dependencies.neo4j
  ++ cognee.optional-dependencies.postgres-binary;

  # Tests require external services
  doCheck = false;

  pythonImportsCheck = [ "src" ];

  meta = {
    changelog = "https://github.com/topoteretes/cognee/releases/tag/${finalAttrs.src.tag}";
    description = "Cognee MCP server";
    homepage = "https://github.com/topoteretes/cognee/tree/main/cognee-mcp";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [ mulatta ];
  };
})
