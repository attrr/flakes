{
  config,
  lib,
  ...
}:
let
  knot = config.infra.knot;
  cfg = knot.slave;
in
{
  options.infra.knot.slave = {
    enable = lib.mkEnableOption "Knot DNS slave";

    masterIPs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Master IP addresses for AXFR/IXFR and NOTIFY.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.knot.settings = {
      remote = [
        {
          id = "master";
          address = cfg.masterIPs;
          key = "transfer-key";
        }
      ];

      acl = [
        {
          id = "allow-notify";
          address = cfg.masterIPs;
          action = "notify";
          key = [ "transfer-key" ];
        }
      ];

      zone = [
        {
          domain = knot.domain;
          master = [ "master" ];
          acl = [ "allow-notify" ];
        }
      ];
    };
  };
}
