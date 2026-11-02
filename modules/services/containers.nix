{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.containers;
in
{
  options.infra.containers = {
    enable = lib.mkEnableOption "podman, with subordinate ids for UserNS=auto";
  };

  config = lib.mkIf cfg.enable {
    virtualisation = {
      containers.enable = true;
      podman.enable = true;
      oci-containers.backend = "podman";
    };

    # for netns=auto
    users = {
      users.containers = {
        isSystemUser = true;
        group = "containers";
        subUidRanges = [
          {
            startUid = 2147483647;
            count = 2147483648;
          }
        ];
        subGidRanges = [
          {
            startGid = 2147483647;
            count = 2147483648;
          }
        ];
      };
      groups.containers = { };
    };

    # restore network on sysctl change
    boot.kernel.sysctl = {
      "net.ipv4.ip_forward" = lib.mkDefault 1;
      "net.ipv4.conf.all.forwarding" = 1;
    };
    systemd.services.podman-network-restore = {
      description = "Restore Podman networking after sysctl overwrites";
      # Bind directly to the sysctl service
      partOf = [ "systemd-sysctl.service" ];
      wantedBy = [ "systemd-sysctl.service" ];
      after = [ "systemd-sysctl.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.podman}/bin/podman network reload --all";
      };
    };
  };
}
