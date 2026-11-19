{
  config,
  lib,
  pkgs,
  ...
}:
let
  knot = config.infra.knot;
  cfg = knot.master;
  slaveIds = map (name: "slave-${name}") (lib.attrNames cfg.slaves);
  slavesIPs = lib.concatLists (lib.attrValues cfg.slaves);
  backupPath = "/var/lib/knot/backup";
in
{
  options.infra.knot.master = {
    enable = lib.mkEnableOption "Knot DNS master";

    slaves = lib.mkOption {
      type = lib.types.attrsOf (lib.types.listOf lib.types.str);
      default = { };
      description = "Map of slave host name to its tailnet IP addresses.";
    };

    backup.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Back up Knot zones via restic.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.knot.settings = {
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

      template.default = {
        serial-policy = "dateserial";
        default-ttl = 3600;
        dnssec-signing = "on";
        dnssec-policy = "standard";
        semantic-checks = "on";
      };

      zone = [
        {
          domain = knot.domain;
          file = "${knot.domain}.zone";
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
      }) cfg.slaves;

      acl = [
        {
          id = "allow-transfer";
          address = slavesIPs;
          action = "transfer"; # Allow AXFR/IXFR
          key = [ "transfer-key" ]; # Only allow if IP matches AND the TSIG key is valid
        }
      ];
    };

    # backups
    infra.restic.backups.knot = lib.mkIf cfg.backup.enable {
      # probably systemd restriction
      paths = [ backupPath ];
      backupPrepareCommand = ''
        rm -rf ${backupPath}
        mkdir -p ${backupPath}
        chown knot:knot ${backupPath}
        ${pkgs.knot-dns}/bin/knotc zone-backup +backupdir ${backupPath}
      '';
      backupCleanupCommand = ''
        rm -rf ${backupPath}
      '';
    };
  };
}
