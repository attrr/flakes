{ ctx, ... }:
{
  # LAN only for the LAN; route and dns go over wg0
  services.resolved.enable = true;
  networking.networkmanager = {
    settings.main.no-auto-default = "*";
    ensureProfiles.profiles.lan =
      let
        lanOnly = {
          method = "auto";
          ignore-auto-dns = true;
          ignore-auto-routes = true;
          never-default = true;
        };
      in
      {
        connection = {
          id = "lan";
          type = "ethernet";
          interface-name = ctx.network.interface;
        };
        ipv4 = lanOnly;
        ipv6 = lanOnly;
      };
  };

}
