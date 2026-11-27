# option modules, inert until enabled; opinionated config lives in ./profiles
{
  common = [
    ./services/htop
    ./services/unfree
  ];

  os = [
    ./network
    ./services/nano-exporter
    ./services/secrets
    ./services/sing-box
    ./services/ssh
    ./services/telemetry
    ./services/tunnelbroker
    ./services/usque
  ];

  nixos = [
    ./disko
    ./services/acme
    ./services/alerts
    ./services/caddy
    ./services/containers
    ./services/knot
    ./services/librechat
    ./services/librechat-rag-api
    ./services/mediawiki
    ./services/nix
    ./services/openbao
    ./services/pooper-scooper
    ./services/quadlet
    ./services/restic
    ./services/serial
    ./services/tailscale
    ./services/tgu
  ];

  finix = [
    ./finix/base.nix
    ./finix/shims.nix
    ./finix/compat.nix
    ./finix/sops.nix
    ./finix/services/openssh.nix
    ./finix/services/sing-box.nix
  ];

  homeManager = [ ];
}
