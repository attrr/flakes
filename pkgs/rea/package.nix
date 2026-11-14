{
  lib,
  buildNpmPackage,
  fetchurl,
  jq,
  nodejs_24,
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
