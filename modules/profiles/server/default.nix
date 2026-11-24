# Multi-class `infra.server` feature (pure profile + ctx wiring).
{
  module = {
    common =
      { lib, ... }:
      {
        options.infra.server = {
          hostname = lib.mkOption {
            type = lib.types.str;
            default = "mini";
          };
          user = lib.mkOption {
            type = lib.types.str;
            default = "sysadm";
            description = "Admin user allowed to SSH in with passwordless sudo.";
          };
          ssh-ports = lib.mkOption {
            type = lib.types.listOf lib.types.port;
            default = [ 22 ];
          };
          ssh-keys = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };

    nixos =
      {
        config,
        lib,
        modulesPath,
        ...
      }:
      let
        cfg = config.infra.server;
      in
      {
        imports = [
          (modulesPath + "/profiles/minimal.nix")
          (modulesPath + "/profiles/headless.nix")
          ../base
          ./lowend.nix
        ];

        options.infra.server = {
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
            # wheel means ssh-key-only admin accounts (deploy-rs sudoes through
            # them), services never are
            security.sudo.wheelNeedsPassword = false;

            # resource journald saving
            services.journald.extraConfig = lib.mkDefault ''
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
          { infra.containers.enable = lib.mkDefault cfg.containers; }
        ];
      };

    finix =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      let
        cfg = config.infra.server;
      in
      {
        config = {
          networking.hostName = lib.mkDefault cfg.hostname;
          providers.firewall.allowedTCPPorts = lib.mkIf (
            config.providers.firewall.backend != "none"
          ) cfg.ssh-ports;

          services.openssh = {
            enable = lib.mkDefault true;
            settings = {
              Port = cfg.ssh-ports;
              PasswordAuthentication = false;
              KbdInteractiveAuthentication = false;
              PermitRootLogin = lib.mkDefault "no";
              AllowUsers = [ cfg.user ];
              AuthorizedKeysFile = [ "/etc/ssh/authorized_keys.d/%u" ];
              UsePAM = true;
              # Point directly at `/etc/ssh/ssh_host_ed25519_key` (provisioned by bootstrap identity-image)
              HostKey = lib.mkForce [ "/etc/ssh/ssh_host_ed25519_key" ];
            };
          };

          finit.tasks.ssh-keygen.command = lib.mkForce (
            pkgs.writeShellScript "ssh-keygen.sh" ''
              mkdir -p /etc/ssh
              if ! [ -s /etc/ssh/ssh_host_ed25519_key ]; then
                ${config.services.openssh.package}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
              fi
            ''
          );

          environment.etc."ssh/authorized_keys.d/${cfg.user}" = lib.mkIf (cfg.ssh-keys != [ ]) {
            mode = "0444";
            text = lib.concatStringsSep "\n" cfg.ssh-keys + "\n";
          };
        };
      };
  };

  ctx = {
    common =
      { ctx, lib, ... }:
      {
        infra.server = {
          hostname = lib.mkDefault ctx.metadata.hostname;
          ssh-ports = lib.mkDefault ctx.ssh.ports;
          ssh-keys = lib.mkDefault ctx.ssh.auth-keys;
        };
      };

    nixos =
      { ctx, lib, ... }:
      {
        infra.server.lowend.enable = lib.mkIf (
          ctx.metadata.specs.memory != null && ctx.metadata.specs.memory <= 1024
        ) (lib.mkDefault true);
      };
  };
}
