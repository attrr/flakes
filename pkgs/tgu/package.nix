{
  python3Packages,
  lib,
  gallery-dl,
}:

python3Packages.buildPythonApplication {
  pname = "tgu";
  version = "0.1.0";
  pyproject = true;

  src = fetchGit {
    url = "git+ssh://git@github.com/attrr/tgu.git";
    rev = "0f11bf694f2dae09bbd9f62f44e0ae51e8756462";
  };

  build-system = with python3Packages; [
    setuptools
  ];

  propagatedBuildInputs = with python3Packages; [
    rich
    httpx
    socksio
    telethon
    tenacity
    click
    pillow
    imagehash
  ];

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ gallery-dl ]}"
  ];

  pythonImportsCheck = [ "tgu" ];
  meta.mainProgram = "tgu";
}
