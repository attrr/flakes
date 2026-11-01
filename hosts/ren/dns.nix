{
  ctx,
  global,
  lib,
  pkgs,
  ...
}:
let
  knot = ctx.services.knot;
in
{
  sops.secrets."${knot.tsig-key.name}".owner = "knot";

  services.knot =
    let
      listenAddrs = map (s: s + "@53") ctx.tailscale.ips;
      slaveIds = map (name: "slave-${name}") (lib.attrNames knot.slaves);
      slavesIPs = lib.concatLists (lib.attrValues knot.slaves);
    in
    {
      enable = true;
      keyFiles = [ knot.tsig-key.path ];

      settings = {

        server = {
          listen = listenAddrs;
          user = "knot";
        };
        log = [
          {
            target = "syslog";
            any = "info";
          }
        ];

        policy = [
          {
            id = "standard";
            algorithm = "ed25519";
            ksk-lifetime = "365d";
            zsk-lifetime = "30d";
            propagation-delay = "1h";
          }
        ];

        mod-rrl = [
          {
            id = "default";
            rate-limit = 100; # 100 resp/s
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
          serial-policy = "dateserial";
          default-ttl = 3600;
          dnssec-signing = "on";
          dnssec-policy = "standard";
          semantic-checks = "on";
        };

        zone = [
          {
            domain = global.domain.main;
            file = "${global.domain.main}.zone";
            notify = slaveIds;
            acl = [ "allow-transfer" ];
            zonefile-load = "difference";
          }
        ];

        # slaves
        remote = lib.mapAttrsToList (name: ips: {
          id = "slave-${name}";
          address = ips;
          key = "transfer-key";
        }) knot.slaves;
        acl = [
          {
            id = "allow-transfer";
            address = slavesIPs;
            action = "transfer"; # Allow AXFR/IXFR
            key = [ "transfer-key" ]; # Only allow if IP matches AND the TSIG key is valid
          }
        ];
      };
    };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };

  # backups
  infra.restic.backups.knot =
    let
      # probably systemd restriction
      path = "/var/lib/knot/backup";
    in
    {
      paths = [ path ];
      backupPrepareCommand = ''
        rm -rf ${path}
        mkdir -p ${path}
        chown knot:knot ${path}
        ${pkgs.knot-dns}/bin/knotc zone-backup +backupdir ${path}
      '';
      backupCleanupCommand = ''
        rm -rf ${path}
      '';
    };
}
