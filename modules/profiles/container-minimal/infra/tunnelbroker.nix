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
    mkdir -p /var/run/wireguard /run/wireguard
    rm -f /var/run/wireguard/${tun.interface}.sock /run/wireguard/${tun.interface}.sock

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
  options.infra.tunnelbroker = {
    enable = lib.mkEnableOption "IPv6 uplink tunnel";
    type = lib.mkOption {
      type = lib.types.enum [ "wireguard" ];
      default = "wireguard";
    };
    interface = lib.mkOption {
      type = lib.types.str;
      default = "ipv6-tun";
    };
    addresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    # Accepted for `modules/ctx/network.nix` compatibility; unused in WireGuard-only container-minimal.
    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    remote = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    # Accepted for `modules/ctx/network.nix` compatibility; unused in WireGuard-only container-minimal.
    local = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "2606:4700:4700::1111" ];
      description = "Resolvers used while the tunnel is the only uplink (IPv6-only).";
    };
    mtu = lib.mkOption {
      type = lib.types.int;
      default = 1420;
    };
    wireguard = {
      privateKeyFile = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      peerPublicKey = lib.mkOption {
        type = lib.types.str;
        default = "";
      };
      persistentKeepalive = lib.mkOption {
        type = lib.types.int;
        default = 25;
      };
    };
  };

  config = lib.mkIf tun.enable {
    finit.tasks.tunnelbroker = lib.mkIf cap.net_admin {
      description = "bring up WireGuard tunnel (${tun.interface}) via boringtun-cli";
      priority = 1100;
      command = "${tunnelUp}";
    };
  };
}
