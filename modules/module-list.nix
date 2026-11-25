# option modules, inert until enabled; opinionated config lives in ./profiles
{
  common = [
    ./network
    ./secrets.nix
    ./services/nano-exporter
    ./services/sing-box
    ./services/telemetry
    ./services/tunnelbroker
    ./services/usque
  ];

  nixos = [
    ./disko
    ./services/acme
    ./services/alerts
    ./services/containers
    ./services/knot
    ./services/librechat
    ./services/librechat-rag-api
    ./services/mediawiki
    ./services/openbao
    ./services/pooper-scooper
    ./services/quadlet
    ./services/restic
    ./services/ssh
    ./services/tgu
    ./services/unfree
  ];

  finix = [
    ./finix/base.nix
    ./finix/shims.nix
    ./finix/compat.nix
    ./finix/sops.nix
    ./finix/services/sing-box.nix
  ];
}
