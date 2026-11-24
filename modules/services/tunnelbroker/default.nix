# Multi-class `infra.tunnelbroker` module (NixOS sit/wireguard + finix boringtun-cli).
{
  common =
    { config, lib, ... }:
    let
      cfg = config.infra.tunnelbroker;
    in
    {
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
    };

  nixos = {
    imports = [
      ./sit.nix
      ./wireguard.nix
    ];
  };

  finix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      tun = config.infra.tunnelbroker;
      cap = config.infra.container.capabilities;
      coreutils = config.programs.coreutils.package;
      iface = lib.escapeShellArg tun.interface;
      ip = "${pkgs.iproute2}/bin/ip";
      wg = "${pkgs.wireguard-tools}/bin/wg";
      boringtun = "${pkgs.boringtun}/bin/boringtun-cli";

      tunnelUp = pkgs.writeShellScript "tunnelbroker-up" ''
        set -eu
        ${coreutils}/bin/pkill -9 -x boringtun-cli 2>/dev/null || true
        ${ip} link del ${iface} 2>/dev/null || true
        rm -f /run/wireguard/${tun.interface}.sock

        WG_SUDO=1 WG_THREADS=1 ${boringtun} --disable-drop-privileges -t 1 ${iface}
        ${wg} set ${iface} \
          private-key ${lib.escapeShellArg tun.wireguard.privateKeyFile} \
          peer ${lib.escapeShellArg tun.wireguard.peerPublicKey} \
          endpoint ${lib.escapeShellArg tun.remote} \
          allowed-ips ::/0 \
          persistent-keepalive ${toString tun.wireguard.persistentKeepalive}
        ${ip} link set dev ${iface} mtu ${toString tun.mtu} up
        ${lib.concatMapStrings (addr: ''
          ${ip} -6 addr replace ${lib.escapeShellArg addr} dev ${iface}
        '') tun.addresses}
        ${ip} -6 route replace ::/0 dev ${iface}
      '';
    in
    {
      config = lib.mkIf tun.enable {
        assertions = [
          {
            assertion = tun.type == "wireguard";
            message = "finix infra.tunnelbroker only supports type = \"wireguard\"";
          }
        ];

        finit.tmpfiles.rules = lib.mkIf cap.net_admin [
          "d /run/wireguard 0755 - -"
        ];

        finit.tasks.tunnelbroker = lib.mkIf cap.net_admin {
          description = "bring up WireGuard tunnel (${tun.interface}) via boringtun-cli";
          conditions = lib.optionals config.programs.ifupdown-ng.enable [ "task/ifupdown-ng/success" ];
          remain-after-exit = true;
          command = "${tunnelUp}";
        };
      };
    };
}
