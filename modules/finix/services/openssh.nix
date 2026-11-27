{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.openssh;
  usersWithKeys = lib.filterAttrs (_: u: u.openssh.authorizedKeys.keys != [ ]) config.users.users;
in
{
  options = {
    services.openssh.ports = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ 22 ];
    };

    users.users = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule (
          { config, ... }:
          {
            options.openssh.authorizedKeys.keys = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
            };
            config.password = lib.mkIf (config.openssh.authorizedKeys.keys != [ ]) (lib.mkDefault "!");
          }
        )
      );
    };
  };

  config = lib.mkIf cfg.enable {
    providers.firewall.allowedTCPPorts = lib.mkIf (
      config.providers.firewall.backend != "none"
    ) cfg.ports;

    services.openssh.settings = {
      Port = cfg.ports;
      AuthorizedKeysFile = [ "/etc/ssh/authorized_keys.d/%u" ];
      UsePAM = true;
      # Point directly at `/etc/ssh/ssh_host_ed25519_key` (provisioned by bootstrap identity-image)
      HostKey = lib.mkForce [ "/etc/ssh/ssh_host_ed25519_key" ];
    };

    finit.tasks.ssh-keygen.command = lib.mkForce (
      pkgs.writeShellScript "ssh-keygen.sh" ''
        mkdir -p /etc/ssh
        if ! [ -s /etc/ssh/ssh_host_ed25519_key ]; then
          ${cfg.package}/bin/ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
        fi
      ''
    );

    environment.etc = lib.mapAttrs' (
      name: u:
      lib.nameValuePair "ssh/authorized_keys.d/${name}" {
        mode = "0444";
        text = lib.concatStringsSep "\n" u.openssh.authorizedKeys.keys + "\n";
      }
    ) usersWithKeys;
  };
}
