{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule {
  pname = "loadbalance";
  version = "unstable-2026-04-02";

  src = fetchFromGitHub {
    owner = "qjebbs";
    repo = "sing-box";
    rev = "9265da6a08ce00fa7986a41cae327058906547a4";
    hash = "sha256-GM1yCwEcqrOWDvGUM7TMXUocwe37FDxVO2JIbuehnbM=";
  };

  vendorHash = "sha256-xQhO2UIqrZezSH1XtbayRbLzAE1c+DdQYi1bu63H1lY=";

  tags = [
    "with_gvisor"
    "with_quic"
    "with_dhcp"
    "with_wireguard"
    "with_utls"
    "with_acme"
    "with_clash_api"
  ];

  subPackages = [
    "cmd/sing-box"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X=github.com/sagernet/sing-box/constant.Version=unstable-2026-02-09"
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
}
