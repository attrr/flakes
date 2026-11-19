# DHCP network topology: obtains IPv4/IPv6 via DHCP and Router Advertisements.
# Renders to systemd-networkd or scripted networking based on networking.useNetworkd.
{
  config,
  lib,
  ...
}:
let
  cfg = config.infra.network;
in
{
  config = lib.mkIf (cfg.topology == "dhcp") (
    lib.mkMerge [
      {
        networking.useNetworkd = lib.mkDefault true;
      }

      (lib.mkIf config.networking.useNetworkd {
        systemd.network.networks."10-default" = {
          matchConfig.Name = if cfg.interface != null then cfg.interface else "e*";
          networkConfig = {
            DHCP = "yes";
            IPv6AcceptRA = true;
          };
          dhcpV4Config.UseMTU = true;
          address = cfg.ipv4.addresses ++ cfg.ipv6.addresses;
        };
      })

      (lib.mkIf (!config.networking.useNetworkd) {
        networking =
          if cfg.interface != null then
            {
              useDHCP = false;
              interfaces.${cfg.interface}.useDHCP = true;
            }
          else
            {
              useDHCP = true;
            };
      })
    ]
  );
}
