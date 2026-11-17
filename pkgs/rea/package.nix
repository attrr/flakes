{
  lib,
  buildNpmPackage,
  fetchurl,
  fetchFromGitHub,
  jq,
  nodejs_24,
  makeWrapper,
  procps,
  util-linux,
  jdk25,
  ghidra,
  jadx-headless-mcp,
  rizin,
  cutter,
  gdb,
  apktool,
  binwalk,
  wireshark-cli,
  ilspycmd,
  xprop,
  wabt,
  python3,
}:

let
  sources = lib.importJSON ./sources.json;

  wabt_1_0_42 = wabt.overrideAttrs (old: rec {
    version = "1.0.42";
    src = fetchFromGitHub {
      owner = "WebAssembly";
      repo = "wabt";
      tag = version;
      fetchSubmodules = true;
      hash = "sha256-33XpYt42Jw2xfwBR64jVI3VYVIKD1YjND9SSI6CdkaM=";
    };
  });

  pwntoolsPython = python3.withPackages (
    ps:
    let
      pyelftools_0_33 = ps.pyelftools.overridePythonAttrs (old: rec {
        version = "0.33";
        src = fetchFromGitHub {
          owner = "eliben";
          repo = "pyelftools";
          tag = "v${version}";
          hash = "sha256-NqF5A6PRl4uncwNS9j44fIV7ovlljiucvV2Msv0LK/w=";
        };
      });
      unicorn_2_1_2 = ps.unicorn.overridePythonAttrs (old: rec {
        version = "2.1.2";
        src = fetchFromGitHub {
          owner = "unicorn-engine";
          repo = "unicorn";
          tag = version;
          hash = "sha256-qA84xBztyWmt/rUExhhZMkQzvDPx0UE9MAIPG/Su3iE=";
        };
        postPatch = (old.postPatch or "") + ''
          substituteInPlace pyproject.toml \
            --replace-fail ', "versioningit"' "" \
            --replace-fail 'dynamic = ["version"]' 'version = "${version}"'
        '';
      });
      pwntools' = ps.pwntools.override {
        pyelftools = pyelftools_0_33;
        unicorn = unicorn_2_1_2;
      };
    in
    [
      pwntools'
      pyelftools_0_33
      unicorn_2_1_2
    ]
  );

  prlimitBin = lib.getExe' util-linux "prlimit";
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
      --prefix PATH : ${
        lib.makeBinPath [
          procps
          util-linux
          rizin
          cutter
          gdb
          apktool
          binwalk
          wireshark-cli
          ilspycmd
          xprop
          wabt_1_0_42
        ]
      } \
      --set-default JAVA_HOME ${jdk25.home} \
      --set-default GHIDRA_INSTALL_DIR ${ghidra}/lib/ghidra \
      --set-default REA_JADX_MCP_JAR ${jadx-headless-mcp}/share/java/jadx-headless-mcp-all.jar \
      --set-default REA_RIZIN_COMMAND ${lib.getExe rizin} \
      --set-default REA_GDB_COMMAND ${lib.getExe gdb} \
      --set-default REA_PWNTOOLS_PYTHON ${lib.getExe pwntoolsPython} \
      --set-default REA_WABT_BIN_DIRECTORY ${wabt_1_0_42}/bin \
      --set-default REA_APKTOOL_COMMAND ${lib.getExe apktool} \
      --set-default REA_BINWALK_COMMAND ${lib.getExe binwalk} \
      --set-default REA_FIRMWARE_PRLIMIT_COMMAND ${prlimitBin} \
      --set-default REA_TSHARK_COMMAND ${lib.getExe' wireshark-cli "tshark"} \
      --set-default REA_CAPINFOS_COMMAND ${lib.getExe' wireshark-cli "capinfos"} \
      --set-default REA_TSHARK_PRLIMIT_COMMAND ${prlimitBin} \
      --set-default REA_ILSPY_CMD_PATH ${lib.getExe ilspycmd} \
      --set-default REA_XPROP_COMMAND ${lib.getExe xprop}
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
