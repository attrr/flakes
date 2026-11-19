{
  lib,
  python3,
  stdenvNoCC,
}:

let
  pythonEnv = python3.withPackages (ps: [
    ps.requests
    ps.beautifulsoup4
  ]);
in
stdenvNoCC.mkDerivation {
  pname = "fl-watch";
  version = "0.1.0";

  dontUnpack = true;

  installPhase = ''
    install -Dm755 ${./fl_watch.py} $out/bin/fl-watch
    substituteInPlace $out/bin/fl-watch \
      --replace-fail "#!/usr/bin/env python3" "#!${pythonEnv}/bin/python3"
  '';

  meta = {
    description = "FileList homepage news and shop price watcher with Telegram notifications";
    mainProgram = "fl-watch";
  };
}
