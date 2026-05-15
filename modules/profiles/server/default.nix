{
  config,
  self,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.core.server;
in
{
  imports = [
    (modulesPath + "/profiles/minimal.nix")
    (modulesPath + "/profiles/headless.nix")
    "${self}/modules/profile/base"
    "${self}/modules/services/ssh.nix"
    ./lowend.nix
  ];

  options.core.server = {
    hostname = lib.mkOption {
      type = lib.types.str;
    };

    ssh-ports = lib.mkOption {
      type = lib.types.listOf lib.types.port;
    };
    ssh-keys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
    };

    serial = lib.mkEnableOption "config serial port";
    auto-resize = lib.mkEnableOption "resize filesystem";
    containers = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkMerge [
    {
      networking.hostName = cfg.hostname;

      services.openssh = {
        enable = true;
        ports = cfg.ssh-ports;
        users.sysadm.authorizedKeys = cfg.ssh-keys;
        lockRootLogin = lib.mkDefault true;
      };

      # resource journald saving
      services.journald.extraConfig = ''
        Storage=persistent
        SystemMaxUse=100M
        SystemMaxFileSize=10M
        MaxRetentionSec=2week
      '';

      # auto grow partition
      boot.growPartition = lib.mkIf cfg.auto-resize true;
      fileSystems."/".autoResize = lib.mkIf cfg.auto-resize true;
    }
    (lib.mkIf cfg.serial (
      let
        sdboot = config.boot.loader.systemd-boot.enable;
        grub = config.boot.loader.grub.enable;
      in
      {
        boot.kernelParams = [
          "console=ttyS0,115200n8"
          "console=tty1"
          "earlycon=uart8250,io,0x3f8,115200n8"
        ];

        boot.loader.systemd-boot.consoleMode = lib.mkIf sdboot "auto";
        boot.loader.grub.extraConfig = lib.mkIf grub ''
          serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
          terminal_input serial
          terminal_output serial
        '';

        # override headless.nix
        systemd.services."serial-getty@ttyS0".enable = true;
      }
    ))
    (lib.mkIf cfg.containers {
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
    })
  ];
}
