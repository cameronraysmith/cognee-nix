{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  setuptools,
  cmake,
  ninja,
  pytestCheckHook,
}:

buildPythonPackage (finalAttrs: {
  pname = "ladybug";
  version = "0.16.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "LadybugDB";
    repo = "ladybug";
    tag = "v${finalAttrs.version}";
    fetchSubmodules = true;
    hash = "sha256-7d6xDsvE+8Ld84E6Gvdr94qSY5zEZLtuZpBVlHlPCeA=";
  };

  sourceRoot = "${finalAttrs.src.name}/tools/python_api";

  postUnpack = ''
    chmod -R +w ${finalAttrs.src.name}
  '';

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'version = "0.0.1"' 'version = "${finalAttrs.version}"'

    # Ensure the compiled extension shipped into src_py is included by setuptools.
    # Upstream's package-data only lists py.typed; append shared-library globs.
    substituteInPlace pyproject.toml \
      --replace-fail 'ladybug = ["py.typed"]' 'ladybug = ["py.typed", "*.so", "*.dylib", "*.pyd"]'
  '';

  build-system = [ setuptools ];

  # cmake and ninja drive the pybind extension build performed in preBuild.
  nativeBuildInputs = [
    cmake
    ninja
  ];

  dontUseCmakeConfigure = true;

  # Build the _lbug pybind module by configuring the parent project with
  # BUILD_PYTHON=TRUE; the root CMakeLists.txt then descends into
  # tools/python_api as a subdirectory, where set_target_properties writes
  # the extension into tools/python_api/build/ladybug.
  preBuild = ''
    cmake -S ../.. -B ../../cmake-build -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_PYTHON=TRUE \
      -DBUILD_SHELL=FALSE
    cmake --build ../../cmake-build --target _lbug

    # setuptools maps the `ladybug` package to src_py via [tool.setuptools.package-dir].
    # Move the compiled extension into src_py so it is picked up at install time.
    cp build/ladybug/_lbug*.so src_py/ 2>/dev/null || \
      cp build/ladybug/_lbug*.dylib src_py/ 2>/dev/null || \
      cp build/ladybug/_lbug*.pyd src_py/ 2>/dev/null || \
      (echo "no _lbug extension artifact found under build/ladybug" >&2; exit 1)
  '';

  nativeCheckInputs = [
    pytestCheckHook
  ];

  enabledTestPaths = [
    "test/"
  ];

  disabledTests = [
    # Subprocess tests spawn new processes where build_dir may not resolve
    "test_database_close"
    "test_database_context_manager"
  ];

  disabledTestPaths = [
    # Tests requiring dataset fixtures (conn_db_readonly/conn_db_readwrite)
    # which fail due to path resolution issues in init_demo within the sandbox
    "test/test_arrow.py"
    "test/test_arrow_memory_backed_table.py"
    "test/test_async_connection.py"
    "test/test_connection.py"
    "test/test_datatype.py"
    "test/test_df.py"
    "test/test_exception.py"
    "test/test_get_header.py"
    "test/test_issue.py"
    "test/test_networkx.py"
    "test/test_parameter.py"
    "test/test_prepared_statement.py"
    "test/test_query_result.py"
    "test/test_timeout.py"
    "test/test_udf.py"
    # Tests requiring optional dependencies (pandas, polars, pyarrow, torch)
    "test/test_scan_pandas.py"
    "test/test_scan_pandas_pyarrow.py"
    "test/test_scan_polars.py"
    "test/test_scan_pyarrow.py"
    "test/test_torch_geometric.py"
    "test/test_torch_geometric_remote_backend.py"
    # Subprocess tests that spawn new Python processes with build_dir
    "test/test_query_result_close.py"
    "test/test_wal.py"
  ];

  pythonImportsCheck = [ "ladybug" ];

  meta = {
    description = "Python bindings for LadybugDB, an embeddable property graph database management system (fork of Kuzu)";
    homepage = "https://ladybugdb.com/";
    changelog = "https://github.com/LadybugDB/ladybug/releases/tag/${finalAttrs.src.tag}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ hamidr ];
  };
})
