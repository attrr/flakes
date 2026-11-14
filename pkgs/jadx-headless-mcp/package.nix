{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  sources = lib.importJSON ./sources.json;
in
stdenvNoCC.mkDerivation {
  pname = "jadx-headless-mcp";
  inherit (sources) version;

  src = fetchurl {
    inherit (sources) url sha256;
  };

  dontUnpack = true;

  installPhase = ''
    runHook preInstall
    install -Dm644 "$src" "$out/share/java/jadx-headless-mcp-all.jar"
    runHook postInstall
  '';

  meta = {
    description = "Headless JADX MCP server JAR for Android APK/DEX analysis";
    homepage = "https://github.com/1013503897/jadx-headless-mcp";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
