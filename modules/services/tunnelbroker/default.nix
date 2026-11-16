# IPv6 uplink tunnel (HE 6in4 sit, Route64 wireguard) layered over the primary IPv4 uplink.
{ config, lib, ... }:
let
  cfg = config.infra.tunnelbroker;
in
{
  imports = [
    ./sit.nix
    ./wireguard.nix
  ];

  options.infra.tunnelbroker = {
    enable = lib.mkEnableOption "IPv6 uplink tunnel";

    type = lib.mkOption {
      type = lib.types.enum [
        "sit"
        "wireguard"
      ];
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "ipv6-tun";
    };

    addresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Local tunnel IPv6 CIDRs (e.g. 2001:db8:1::2/64).";
    };

    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Peer tunnel IPv6 gateway (for sit).";
    };

    remote = lib.mkOption {
      type = lib.types.str;
      description = "Peer endpoint (IPv4 for sit, ip:port for wireguard).";
    };

    local = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Local IPv4 address for sit; null uses any.";
    };

    mtu = lib.mkOption {
      type = lib.types.int;
      default = if cfg.type == "sit" then 1480 else 1420;
    };

    userspace = lib.mkOption {
      type = lib.types.bool;
      default = config.boot.isContainer;
      description = "Run WireGuard tunnel in userspace via boringtun (for containers without kernel WireGuard).";
    };

    wireguard = {
      privateKeyFile = lib.mkOption {
        type = lib.types.str;
      };

      peerPublicKey = lib.mkOption {
        type = lib.types.str;
      };

      persistentKeepalive = lib.mkOption {
        type = lib.types.int;
        default = 25;
      };
    };
  };
}
