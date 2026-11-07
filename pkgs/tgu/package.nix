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
    rev = "d6249b772f88c8e697192c1c6f1ef6d45c9ed310";
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
