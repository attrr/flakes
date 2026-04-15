{
  config,
  options,
  lib,
  ...
}:
let
  cfg = config.core.restic;
  repository = "s3:${cfg.s3.base}/${cfg.s3.bucketName}/${cfg.s3.namespace}";
in
{
  options.core.restic = {
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
              pruneOpts = lib.mkDefault [
                "--group-by host,paths,tags"
                "--tag ${name}"
                "--keep-last 5"
                "--keep-hourly 24"
                "--keep-daily 7"
                "--keep-weekly 5"
                "--keep-monthly 12"
                "--keep-yearly 10"
              ];
              extraOptions = lib.mkDefault [
                "s3.storage-class=ONEZONE_IA"
              ];
              extraBackupArgs = lib.mkDefault [ "--tag ${name}" ];
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
    services.restic.backups = cfg.backups;
  };
}
