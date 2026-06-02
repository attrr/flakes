{
  python3Packages,
  lib,
  gallery-dl,
}:

python3Packages.buildPythonApplication {
  pname = "tgu";
  version = "0.1.0";
  pyproject = true;

  src = builtins.fetchGit {
    url = "git+ssh://git@github.com/attrr/tgu.git";
    rev = "d551fa554f9209ae421e3dcad06a03ebf9c5c06c";
  };

  build-system = with python3Packages; [
    setuptools
  ];

  propagatedBuildInputs = with python3Packages; [
    httpx
    telethon
    click
    pillow
  ];

  makeWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ gallery-dl ]}"
  ];

  pythonImportsCheck = [ "cli" ];
  meta.mainProgram = "tgu";
}
