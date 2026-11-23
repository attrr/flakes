{
  config,
  lib,
  ...
}:
let
  cfg = config.infra.sing-box;
in
{
  imports = [
    ./common.nix
    ./warp-svc.nix
    ./lowend.nix
  ];

  options.infra.sing-box = {
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    isolated = lib.mkOption {
      type = lib.types.bool;
      default = !config.boot.isContainer;
      description = "Run sing-box inside an ephemeral systemd-nspawn container instead of directly on the host.";
    };
  };

  config = lib.mkIf cfg.enable {
    # to match permission inside/outside of container
    users = lib.mkIf cfg.isolated {
      users.sing-box = {
        isSystemUser = true;
        uid = cfg.uid;
        group = "sing-box";
      };
      groups.sing-box = {
        gid = cfg.gid;
      };
    };

    containers.sing-box = lib.mkIf cfg.isolated {
      autoStart = true;
      ephemeral = true;
      privateNetwork = false;

      bindMounts =
        lib.genAttrs
          (builtins.filter (path: path != "" && !(lib.hasPrefix builtins.storeDir path)) cfg.secrets)
          (path: {
            hostPath = path;
            isReadOnly = true;
          });
      config =
        { ... }:
        {
          users.users.sing-box.uid = cfg.uid;
          users.groups.sing-box.gid = cfg.gid;
          services.sing-box = {
            enable = true;
            settings = cfg.settings;
          };
          services.journald.extraConfig = ''
            Storage=volatile
            RuntimeMaxUse=32M
          '';
          system.stateVersion = config.system.stateVersion;
        };
    };

    services.sing-box = lib.mkIf (!cfg.isolated) {
      enable = true;
      settings = cfg.settings;
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = cfg.tcpPorts;
      allowedUDPPorts = cfg.udpPorts;
    };
  };
}
