{
  lib,
  buildPythonPackage,
  fetchFromGitHub,
  pythonOlder,
  setuptools,
  click-default-group,
  condense-json,
  numpy,
  openai,
  pip,
  pluggy,
  puremagic,
  pydantic,
  python-ulid,
  pyyaml,
  sqlite-migrate,
  sqlite-utils
}:
buildPythonPackage rec {
  pname = "llm";
  version = "0.27.1";
  pyproject = true;

  build-system = [ setuptools ];

  disabled = pythonOlder "3.8";

  src = fetchFromGitHub {
    owner = "simonw";
    repo = "llm";
    tag = version;
    hash = "sha256-HWzuPhI+oiCKBeiHK7x9Sc54ZB88Py60FzprMLlZGrY=";
  };

  dependencies = [
    click-default-group
    condense-json
    numpy
    openai
    pip
    pluggy
    puremagic
    pydantic
    python-ulid
    pyyaml
    setuptools # for pkg_resources
    sqlite-migrate
    sqlite-utils
  ];

  doCheck = false;

  pythonImportsCheck = [ "llm" ];

  meta = {
    homepage = "https://github.com/simonw/llm";
    description = "Access large language models from the command-line";
    changelog = "https://github.com/simonw/llm/releases/tag/${src.tag}";
    license = lib.licenses.asl20;
    mainProgram = "llm";
    maintainers = with lib.maintainers; [
      aldoborrero
      mccartykim
      philiptaron
    ];
  };
}