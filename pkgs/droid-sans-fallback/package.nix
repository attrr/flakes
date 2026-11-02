{
  lib,
  stdenvNoCC,
  fetchurl,
}:

# same file as Fedora's google-droid-sans-fonts
stdenvNoCC.mkDerivation {
  pname = "droid-sans-fallback";
  version = "15.0.0_r1";

  src = fetchurl {
    url = "https://github.com/aosp-mirror/platform_frameworks_base/raw/android-15.0.0_r1/data/fonts/DroidSansFallbackFull.ttf";
    hash = "sha256-I5IBVTBDi6/Ejt/ErubZ3iOH9iemE02Ks9/MmdIcgkA=";
  };

  dontUnpack = true;
  installPhase = ''
    install -Dm444 $src $out/share/fonts/truetype/DroidSansFallbackFull.ttf
  '';

  meta = {
    description = "Android's CJK fallback font";
    license = lib.licenses.asl20;
    platforms = lib.platforms.all;
  };
}
