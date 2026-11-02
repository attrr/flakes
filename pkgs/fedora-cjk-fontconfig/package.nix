{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  libxml2,
}:

# Fedora's CJK fontconfig rules, from its dist-git
let
  distgit =
    pkg: rev: file: hash:
    fetchurl {
      name = file;
      url = "https://src.fedoraproject.org/rpms/${pkg}/raw/${rev}/f/${file}";
      inherit hash;
    };

  sans = distgit "google-noto-sans-cjk-vf-fonts" "3ed6b918569dbd0fd65e0c9543f97cc32b5b1f07";
  serif = distgit "google-noto-serif-cjk-vf-fonts" "320bd70d1c1d1144acb2ca465c5b66f0de7c0a97";
  droid = distgit "google-droid-fonts" "1bd6a6e9d3aae1c93c39a901e5051016b60cef36";

  genfontconf = sans "genfontconf.py" "sha256-En71wPsa6NBZisIQtkY3Yr9ehK561Ka84daCS085pE8=";
  confs = [
    (sans "65-google-noto-sans-cjk-vf-fonts.conf" "sha256-3srJ3RZUBWd7DcKAxibFZ2xJ9mPjLIt4lEOQR5sKqEw=")
    (sans "65-google-noto-sans-mono-cjk-vf-fonts.conf" "sha256-6BJgETQ5IhvcINfwMWbjv7hGbOmHsEYTCZVJsgOPk2A=")
    (serif "65-google-noto-serif-cjk-vf-fonts.conf" "sha256-FXujL8n5sHQFfouicflM21q0pPIt5U10IhbosXFs+7o=")
    (droid "69-google-droid-sans-fallback-fonts.conf" "sha256-QXzo6KowIAnb2Tk+VpVQl7sBQ4rYXCo5N7gsrQcC/jE=")
  ];

  # as in the specs' %prep
  gen = generic: family: ''
    python3 ${genfontconf} \
      "ja" "${generic}" "${family} JP" \
      "ko" "${generic}" "${family} KR" \
      "zh-cn:zh-sg" "${generic}" "${family} SC" \
      "zh-tw:cmn:hak:lzh:nan" "${generic}" "${family} TC" \
      "zh-hk:zh-mo:yue" "${generic}" "${family} HK" \
  '';
in
stdenvNoCC.mkDerivation {
  pname = "fedora-cjk-fontconfig";
  version = "44";

  dontUnpack = true;
  nativeBuildInputs = [
    python3
    libxml2
  ];

  buildPhase = ''
    ${gen "sans-serif" "Noto Sans CJK"} | xmllint --format - > 65-0-google-noto-sans-cjk-vf-fonts.conf
    ${gen "monospace" "Noto Sans Mono CJK"} | xmllint --format - > 65-0-google-noto-sans-mono-cjk-vf-fonts.conf
    ${gen "serif" "Noto Serif CJK"} | xmllint --format - > 65-0-google-noto-serif-cjk-vf-fonts.conf
  '';

  installPhase = ''
    install -Dm444 -t $out/etc/fonts/conf.d 65-0-*.conf
    ${lib.concatMapStrings (c: "install -Dm444 ${c} $out/etc/fonts/conf.d/${c.name}\n") confs}
  '';

  meta = {
    description = "Fedora's fontconfig rules for Noto CJK and Droid Sans Fallback";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
