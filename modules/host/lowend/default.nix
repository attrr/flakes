{
  lib,
  config,
  failoverModule,
  ...
}:
let
  cfg = config.cloud.server;
in
{
  imports = [
    ./disko.nix
    ../server.nix
    failoverModule
  ];

  options.cloud.server = {
    zram-percent = lib.mkOption {
      type = lib.types.int;
      default = 100;
    };
  };

  config = {
    zramSwap.memoryPercent = cfg.zram-percent;
    cloud.server.auto-resize = true;

    services.failover = {
      enable = true;
      rescue.ssh.authorizedKeys = cfg.ssh-keys;
    };
  };
}
