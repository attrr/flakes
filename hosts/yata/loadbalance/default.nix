{
  config,
  lib,
  pkgs,
  ctx,
  fn,
  ...
}@args:
let
  cfg = config.services.loadbalance;

  loadbalanceConfigFile = import ./config.nix args;

  # Merge providerConfig and mainConfig into a single loadbalanceConfig
  loadbalanceConfig = {
    inherit (loadbalanceConfigFile.mainConfig)
      log
      dns
      inbounds
      route
      experimental
      ;
    inherit (loadbalanceConfigFile.providerConfig)
      providers
      ;
    outbounds =
      loadbalanceConfigFile.mainConfig.outbounds ++ loadbalanceConfigFile.providerConfig.outbounds;
  };
in
{
  options.services.loadbalance = {
    enable = lib.mkEnableOption "loadbalance service (qjebbs sing-box fork)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../../pkgs/loadbalance/default.nix { };
      description = "The loadbalance package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Use sops templates to inject secrets
    sops.templates."loadbalance.json" = {
      content = builtins.toJSON loadbalanceConfig;
      owner = "loadbalance";
    };

    # from nixpkgs
    environment.systemPackages = [ cfg.package ];
    services.dbus.packages = [ cfg.package ];
    systemd.packages = [ cfg.package ];

    systemd.services.loadbalance = {
      description = "Loadbalance Service (qjebbs sing-box fork)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        User = "loadbalance";
        Group = "loadbalance";
        StateDirectory = "loadbalance";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "loadbalance";
        RuntimeDirectoryMode = "0700";
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/lib/loadbalance/providers";
        ExecStart = "${lib.getExe cfg.package} -D \${STATE_DIRECTORY} -C \${RUNTIME_DIRECTORY} run -c ${
          config.sops.templates."loadbalance.json".path
        }";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    users.users.loadbalance = {
      isSystemUser = true;
      group = "loadbalance";
      home = "/var/lib/loadbalance";
    };
    users.groups.loadbalance = { };
  };
}
