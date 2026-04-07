{
  lib,
  python3Packages,
}:

python3Packages.buildPythonApplication {
  pname = "pooper-scooper";
  version = "0.1.1";

  src = ../../src/pooper-scooper;

  propagatedBuildInputs = with python3Packages; [
    fastapi
    uvicorn
    httpx
    pydantic
  ];

  format = "other";

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    cp main_fastapi.py $out/bin/pooper-scooper
    chmod +x $out/bin/pooper-scooper

    runHook postInstall
  '';

  meta = with lib; {
    description = "A simple proxy subscription cleaner";
    license = licenses.mit;
    mainProgram = "pooper-scooper";
  };
}
