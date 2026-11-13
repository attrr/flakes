{ ctx, global, ... }:
{
  sops.secrets."${ctx.services.knot.tsig-key.name}".owner = "knot";
  services.knot =
    let
      listenAddrs = map (s: s + "@53") ctx.tailscale.ips;
      masterIPs = ctx.services.knot.master-ips;
    in
    {
      enable = true;
      keyFiles = [ ctx.services.knot.tsig-key.path ];

      settings = {
        server = {
          listen = listenAddrs;
          user = "knot";
        };

        mod-rrl = [
          {
            id = "default";
            rate-limit = 100;
            slip = 2;
          }
        ];
        mod-cookies = [
          {
            id = "default";
            secret-lifetime = "30h";
            badcookie-slip = 3;
          }
        ];

        template.default = {
          global-module = [
            "mod-rrl/default"
            "mod-cookies/default"
          ];
          storage = "/var/lib/knot/zones";
        };

        remote = [
          {
            id = "master";
            address = masterIPs;
            key = "transfer-key";
          }
        ];
        acl = [
          {
            id = "allow-notify";
            address = masterIPs;
            action = "notify";
            key = [ "transfer-key" ];
          }
        ];
        zone = [
          {
            domain = global.domain.main;
            master = [ "master" ];
            acl = [ "allow-notify" ];
          }
        ];
      };
    };
  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
