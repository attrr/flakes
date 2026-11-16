# WireGuard IPv6 tunnel (kernel networking.wireguard, or wg-quick + boringtun in containers).
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.tunnelbroker;
  active = cfg.enable && cfg.type == "wireguard";
  peers = [
    {
      publicKey = cfg.wireguard.peerPublicKey;
      endpoint = cfg.remote;
      allowedIPs = [ "::/0" ];
      persistentKeepalive = cfg.wireguard.persistentKeepalive;
    }
  ];
in
{
  config = lib.mkIf active (
    lib.mkMerge [
      (lib.mkIf cfg.userspace {
        networking.wg-quick.interfaces.${cfg.interface} = {
          address = cfg.addresses;
          inherit (cfg) mtu;
          table = "main";
          inherit (cfg.wireguard) privateKeyFile;
          inherit peers;
        };

        systemd.services."wg-quick-${cfg.interface}" = {
          path = [ pkgs.boringtun ];
          environment = {
            WG_QUICK_USERSPACE_IMPLEMENTATION = "boringtun-cli";
            WG_SUDO = "1";
            WG_THREADS = "1";
          };
        };
      })
      (lib.mkIf (!cfg.userspace) {
        networking.wireguard.interfaces.${cfg.interface} = {
          ips = cfg.addresses;
          inherit (cfg) mtu;
          inherit (cfg.wireguard) privateKeyFile;
          inherit peers;
        };
      })
    ]
  );
}
