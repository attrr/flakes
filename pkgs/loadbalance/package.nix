{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

# bump to the fork's main (its own releases aren't versions, hence the regex):
#   nix run nixpkgs#nix-update -- --flake legacyPackages.x86_64-linux.loadbalance --version=branch --version-regex '^v?([0-9].*)$'
buildGoModule (finalAttrs: {
  pname = "loadbalance";
  version = "1.15.0-alpha.13-unstable-2026-11-08";

  src = fetchFromGitHub {
    owner = "qjebbs";
    repo = "sing-box";
    rev = "c323c7818e4d991ee8fe765ebfa0b2e9fe40043c";
    hash = "sha256-jRsw70jqFYFE9Ehp35UIARQbx56qbH66TQIdaddcfAg=";
  };

  vendorHash = "sha256-ipPHWUuYQRwzqfx+qP3oNq5fpojxtimOD19iwj+nHcU=";

  env.CGO_ENABLED = 0;

  tags = [
    "with_gvisor"
    "with_quic"
    "with_dhcp"
    "with_wireguard"
    "with_utls"
    "with_acme"
    "with_clash_api"
    "badlinkname"
    "tfogo_checklinkname0"
  ];

  subPackages = [
    "cmd/sing-box"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/sagernet/sing-box/constant.Version=${finalAttrs.version}"
    "-checklinkname=0"
  ];

  # Rename binary to loadbalance
  postInstall = ''
    mv $out/bin/sing-box $out/bin/loadbalance
  '';

  meta = {
    description = "qjebbs's sing-box fork with load balancing support";
    homepage = "https://github.com/qjebbs/sing-box";
    license = lib.licenses.gpl3Plus;
    mainProgram = "loadbalance";
  };
})
