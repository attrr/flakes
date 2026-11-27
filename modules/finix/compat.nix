{ config, lib, ... }:
{
  options = {
    # finix `modules/networking` omits `nameservers`; declared here for `infra.network`.
    networking.nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };

    security.sudo.wheelNeedsPassword = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
  };

  config = lib.mkMerge [
    {
      # Finit's built-in `tmpfiles` ignores `z` (adjust mode/owner of existing paths) rules;
      # apply them during activation (after `users`) so both boot and `deploy` (`tar --owner=0`) stay consistent.
      system.activation.scripts.tmpfiles-z = {
        deps = [
          "specialfs"
          "users"
          "etc"
        ];
        text = ''
          while read -r type path mode user group _; do
            [ "$type" = "z" ] && [ -e "$path" ] && [ ! -L "$path" ] || continue
            if [ -n "$mode" ] && [ "$mode" != "-" ]; then
              chmod "$mode" "$path"
            fi
            case "''${user:--}:''${group:--}" in
              -:-) ;;
              -:*) chown -h ":$group" "$path" ;;
              *:-) chown -h "$user" "$path" ;;
              *) chown -h "$user:$group" "$path" ;;
            esac
          done < /etc/tmpfiles.d/finix.conf
        '';
      };
    }
    (lib.mkIf (!config.security.sudo.wheelNeedsPassword) {
      programs.sudo.enable = lib.mkDefault true;
      environment.etc.sudoers.text = lib.mkAfter ''
        %wheel ALL=(ALL:ALL) NOPASSWD: SETENV: ALL
      '';
    })
  ];
}
