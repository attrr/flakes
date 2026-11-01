{
  config,
  options,
  lib,
  ...
}:
let
  cfg = config.infra.restic;
  repository = "s3:${cfg.s3.base}/${cfg.s3.bucketName}/${cfg.s3.namespace}";
in
{
  options.infra.restic = {
    enable = lib.mkEnableOption "restic services";
    s3 = {
      base = lib.mkOption {
        type = lib.types.str;
        default = "https://s3.fr-par.scw.cloud";
        description = "s3 endpoint base url";
      };
      bucketName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "s3 bucket name";
      };
      namespace = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        description = "s3 namespace per machine";
      };
    };

    environmentFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };
    passwordFile = lib.mkOption {
      type = with lib.types; nullOr str;
      default = null;
    };

    # prune needs the repo exclusively, so it runs once for every job here
    # instead of after each backup, where the jobs would fight over the lock
    maintenance = {
      pruneOpts = lib.mkOption {
        type = with lib.types; listOf str;
        default = [
          "--group-by host,paths,tags"
          "--keep-last 5"
          "--keep-hourly 24"
          "--keep-daily 7"
          "--keep-weekly 5"
          "--keep-monthly 12"
          "--keep-yearly 10"
        ];
        description = "restic forget --prune options, applied per host/paths/tags group";
      };
      checkOpts = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ "--read-data-subset=5%" ];
        description = "restic check options, run after the prune";
      };
      timerConfig = lib.mkOption {
        type = with lib.types; attrsOf anything;
        default = {
          OnCalendar = "weekly";
          RandomizedDelaySec = "2h";
          Persistent = true;
        };
      };
    };

    backups = lib.mkOption {
      default = { };
      type = lib.types.attrsOf (
        lib.types.submodule (
          { name, ... }:
          {
            imports = options.services.restic.backups.type.nestedTypes.elemType.getSubModules;
            config = {
              inherit repository;
              inherit (cfg) passwordFile environmentFile;
              initialize = lib.mkDefault true;
              extraOptions = lib.mkDefault [
                "s3.storage-class=ONEZONE_IA"
              ];
              # waits out the maintenance job instead of failing
              extraBackupArgs = lib.mkDefault [
                "--tag ${name}"
                "--retry-lock 30m"
              ];
              timerConfig = lib.mkDefault {
                OnCalendar = "daily";
                RandomizedDelaySec = "2h";
                Persistent = true;
              };
            };
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    services.restic.backups = cfg.backups // {
      # no paths: only forget --prune and check
      maintenance = {
        inherit repository;
        inherit (cfg) passwordFile environmentFile;
        inherit (cfg.maintenance) timerConfig;
        pruneOpts = cfg.maintenance.pruneOpts ++ [ "--retry-lock 2h" ];
        checkOpts = cfg.maintenance.checkOpts ++ [ "--retry-lock 2h" ];
      };
    };
  };
}
