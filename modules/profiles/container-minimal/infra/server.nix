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
}
