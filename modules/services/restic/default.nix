{
  module =
    {
      config,
      options,
      lib,
      ...
    }:
    let
      cfg = config.infra.restic;
      repository = "s3:${cfg.s3.base}/${cfg.s3.bucketName}/${cfg.s3.namespace}";

      mkRepoAttrs =
        m:
        lib.optionalAttrs (m.repository != null) { inherit (m) repository; }
        // lib.optionalAttrs (m.repositoryFile != null) { inherit (m) repositoryFile; };

      mkMaintenance =
        target:
        {
          inherit (cfg) passwordFile;
          inherit (target) environmentFile timerConfig;
          pruneOpts = cfg.maintenance.pruneOpts ++ [ "--retry-lock 2h" ];
          checkOpts = cfg.maintenance.checkOpts ++ [ "--retry-lock 2h" ];
        }
        // lib.optionalAttrs (target ? extraOptions) { inherit (target) extraOptions; }
        // mkRepoAttrs target;

      mirrorBackups = lib.concatMapAttrs (
        mName: m:
        let
          target = {
            inherit (m) environmentFile extraOptions timerConfig;
          }
          // mkRepoAttrs m;
        in
        lib.mapAttrs' (
          bName: b:
          lib.nameValuePair "${bName}-${mName}" (
            {
              inherit (b)
                paths
                exclude
                backupPrepareCommand
                backupCleanupCommand
                extraBackupArgs
                initialize
                user
                passwordFile
                ;
            }
            // target
            // lib.optionalAttrs (b.dynamicFilesFrom != null) { inherit (b) dynamicFilesFrom; }
          )
        ) cfg.backups
        // {
          "maintenance-${mName}" = mkMaintenance (m // { timerConfig = m.maintenanceTimerConfig; });
        }
      ) cfg.mirrors;

      mirrorOrderings = lib.concatMapAttrs (
        mName: _:
        lib.mapAttrs' (
          bName: _:
          lib.nameValuePair "restic-backups-${bName}-${mName}" {
            # Avoid colliding with primary job's backupPrepareCommand temp dirs (e.g. sqlite .backup).
            after = [ "restic-backups-${bName}.service" ];
          }
        ) cfg.backups
      ) cfg.mirrors;
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

        mirrors = lib.mkOption {
          default = { };
          description = "Additional peer restic repositories that receive copies of every backup job";
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                repository = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Full restic repository URL for this peer target";
                };
                repositoryFile = lib.mkOption {
                  type = lib.types.nullOr lib.types.str;
                  default = null;
                  description = "Path to a file containing the restic repository URL (keeps credentials out of the Nix store)";
                };
                environmentFile = lib.mkOption {
                  type = with lib.types; nullOr str;
                  default = null;
                };
                extraOptions = lib.mkOption {
                  type = lib.types.listOf lib.types.str;
                  default = [ ];
                };
                timerConfig = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = {
                    OnCalendar = "05:00";
                    RandomizedDelaySec = "1h";
                    Persistent = true;
                  };
                };
                maintenanceTimerConfig = lib.mkOption {
                  type = lib.types.attrsOf lib.types.anything;
                  default = {
                    OnCalendar = "Sun 06:00";
                    RandomizedDelaySec = "2h";
                    Persistent = true;
                  };
                };
              };
            }
          );
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
        infra.alerts.units = map (n: "restic-backups-${n}") (lib.attrNames config.services.restic.backups);

        infra.restic.backups = lib.mkIf (config.infra.acme.enable or false) {
          infra.paths = [ "/var/lib/acme" ];
        };

        services.restic.backups =
          cfg.backups
          // {
            # no paths: only forget --prune and check
            maintenance = mkMaintenance {
              inherit repository;
              repositoryFile = null;
              inherit (cfg) environmentFile;
              inherit (cfg.maintenance) timerConfig;
            };
          }
          // mirrorBackups;

        systemd.services = mirrorOrderings;
      };
    };

  ctx =
    {
      lib,
      ctx,
      ...
    }:
    let
      restic = ctx.services.restic;
    in
    lib.mkIf restic.enable {
      infra.restic = {
        enable = lib.mkDefault true;
        s3.bucketName = lib.mkDefault restic.bucket-name;
        environmentFile = lib.mkDefault restic.env.path;
        passwordFile = lib.mkDefault restic.password.path;
        mirrors = lib.mkIf (restic.rest-repo != null) {
          gdrive.repositoryFile = lib.mkDefault restic.rest-repo.path;
        };
      };
    };
}
