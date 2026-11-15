{
  lib,
  buildNpmPackage,
  fetchurl,
  jq,
  nodejs_24,
  makeWrapper,
  procps,
  jdk21,
  ghidra,
  jadx-headless-mcp,
}:

let
  sources = lib.importJSON ./sources.json;
in
buildNpmPackage {
  pname = "rea";
  inherit (sources) version npmDepsHash;

  src = fetchurl {
    inherit (sources) url hash;
  };

  nodejs = nodejs_24;

  postPatch = ''
    ${lib.getExe jq} 'del(.optionalDependencies, .devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
  '';

  # The npm tarball already ships compiled dist/ and npm-shrinkwrap.json.
  dontNpmBuild = true;
  npmFlags = [ "--ignore-scripts" ];

  nativeBuildInputs = [ makeWrapper ];

  postFixup = ''
    wrapProgram $out/bin/rea \
      --prefix PATH : ${lib.makeBinPath [ procps ]} \
      --set-default JAVA_HOME ${jdk21.home} \
      --set-default GHIDRA_INSTALL_DIR ${ghidra}/lib/ghidra \
      --set-default REA_JADX_MCP_JAR ${jadx-headless-mcp}/share/java/jadx-headless-mcp-all.jar
  '';

  meta = {
    description = "Reverse engineer anything with agents, from app behavior down to native binaries";
    homepage = "https://github.com/morluto/rea";
    changelog = "https://github.com/morluto/rea/releases/tag/v${sources.version}";
    license = lib.licenses.mit;
    mainProgram = "rea";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
