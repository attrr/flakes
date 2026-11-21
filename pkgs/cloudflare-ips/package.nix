{
  lib,
  stdenvNoCC,
  fetchurl,
  python3,
  nix,
  git,
  writers,
}:
let
  sources = lib.importJSON ./sources.json;

  ipsV4 = fetchurl {
    inherit (sources.v4) url hash;
  };

  ipsV6 = fetchurl {
    inherit (sources.v6) url hash;
  };
in
stdenvNoCC.mkDerivation {
  pname = "cloudflare-ips";
  inherit (sources) version;

  dontUnpack = true;
  nativeBuildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall
    python3 ${./generate.py} ${ipsV4} ${ipsV6} "$out/share/cloudflare-ips"
    runHook postInstall
  '';

  passthru.updateScript = writers.writePython3 "update-cloudflare-ips" {
    makeWrapperArgs = [
      "--prefix"
      "PATH"
      ":"
      (lib.makeBinPath [
        nix
        git
      ])
    ];
  } (builtins.readFile ./update.py);

  meta = {
    description = "Cloudflare IPv4 and IPv6 CIDR ranges formatted for Caddy and nftables";
    homepage = "https://www.cloudflare.com/ips/";
    platforms = lib.platforms.all;
  };
}
