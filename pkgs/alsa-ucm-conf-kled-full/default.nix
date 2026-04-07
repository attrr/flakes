{
  stdenv,
  fetchFromGitHub,
  alsa-ucm-conf,
}:

stdenv.mkDerivation {
  pname = "alsa-ucm-conf-kled-full";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "WeirdTreeThing";
    repo = "alsa-ucm-conf-cros";
    rev = "a4e92135fd49e669b5ce096439289e05e25ae90c";
    hash = "sha256-3TpzjmWuOn8+eIdj0BUQk2TeAU7BzPBi3FxAmZ3zkN8=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    target="$out/share/alsa/ucm2"
    mkdir -p "$target"

    # copy base
    cp -r --no-preserve=mode ${alsa-ucm-conf}/share/alsa/ucm2/* "$target/"

    # apply patch
    cp -rf ucm2/* "$target/"
    mkdir -p "$target/conf.d"
    [ -d "overrides" ] && cp -rf overrides/* "$target/conf.d/"

    runHook postInstall
  '';
}
