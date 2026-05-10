{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.loadbalance;
  jsonFormat = pkgs.formats.json { };
  package = pkgs.callPackage ../../../pkgs/loadbalance/default.nix { };
in
{
  imports = [
    ./config.nix
    ./providers.nix
  ];

  options.infra.loadbalance = {
    enable = lib.mkEnableOption "enable loadbalance service";

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = jsonFormat.type;
      };
      default = { };
    };

    # internal
    secrets = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      internal = true;
    };
    providers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/loadbalance 0750 root root -"
    ];

    containers.loadbalance = {
      autoStart = true;
      ephemeral = true;
      privateNetwork = false;

      bindMounts = {
        "/var/lib/sing-box" = {
          hostPath = "/var/lib/loadbalance";
          isReadOnly = false;
        };
      }
      //
        lib.genAttrs
          (builtins.filter (path: path != "" && !(lib.hasPrefix builtins.storeDir path)) cfg.secrets)
          (path: {
            hostPath = path;
            isReadOnly = true;
          });
      config =
        { ... }:
        {
          services.sing-box = {
            enable = true;
            package = package;
            settings = cfg.settings;
          };

          systemd.services.sing-box = {
            serviceConfig = {
              ExecStartPre = [ "${pkgs.coreutils}/bin/mkdir -p /var/lib/sing-box/providers" ];
            };
          };
          system.stateVersion = config.system.stateVersion;
        };
    };
  };
}
