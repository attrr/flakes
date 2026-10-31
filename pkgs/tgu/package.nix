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
    rev = "1f737f8fffb8ff3c42a74a6561416791feba054b";
  };

  build-system = with python3Packages; [
    setuptools
  ];

  propagatedBuildInputs = with python3Packages; [
    anyascii
    rich
    httpx
    socksio
    telethon
    tenacity
    click
    pillow
    pysocks
    imagehash
  ];

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ gallery-dl ]}"
  ];

  pythonImportsCheck = [ "tgu" ];
  meta.mainProgram = "tgu";
}
