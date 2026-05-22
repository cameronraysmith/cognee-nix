{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  # build system
  hatchling,
  hatch-regex-commit,
  pythonRelaxDepsHook,
  # dependencies
  fastapi,
  pwdlib,
  email-validator,
  pyjwt,
  python-multipart,
  makefun,
  # optional dependencies
  httpx-oauth,
  redis,
  # passthru test dependencies
  pytestCheckHook,
  pytest-asyncio,
  pytest-mock,
  httpx,
  asgi-lifespan,
  cryptography,
}:
buildPythonPackage rec {
  pname = "fastapi-users";
  version = "15.0.3";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "fastapi-users";
    repo = "fastapi-users";
    rev = "v${version}";
    hash = "sha256-0Lx7heqwLt7S8CIY5eG6R/76NuhUtbU6yicEnLhuu0Q=";
  };

  build-system = [
    hatchling
    hatch-regex-commit
  ];

  nativeBuildInputs = [ pythonRelaxDepsHook ];

  pythonRelaxDeps = [
    "python-multipart"
    "pyjwt"
  ];

  dependencies = [
    fastapi
    pwdlib
    email-validator
    pyjwt
    python-multipart
    makefun
  ];

  optional-dependencies = {
    oauth = [ httpx-oauth ];
    redis = [ redis ];
  };

  nativeCheckInputs = [
    pytestCheckHook
    pytest-asyncio
    pytest-mock
    httpx
    httpx-oauth
    asgi-lifespan
    cryptography
  ];

  disabledTestPaths = [
    # Requires database backends (sqlalchemy, beanie)
    "tests/test_router_users.py"
    "tests/test_router_auth.py"
    "tests/test_router_register.py"
    "tests/test_router_reset.py"
    "tests/test_router_verify.py"
    "tests/test_router_oauth.py"
    # Requires redis optional dependency
    "tests/test_authentication_strategy_redis.py"
  ];

  pythonImportsCheck = [ "fastapi_users" ];

  meta = {
    description = "Ready-to-use and customizable users management for FastAPI";
    homepage = "https://github.com/fastapi-users/fastapi-users";
    changelog = "https://github.com/fastapi-users/fastapi-users/releases/tag/v${version}";
    license = lib.licenses.mit;
    maintainers = [ ];
  };
}
