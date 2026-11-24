# finix platform polyfills (nameservers option + tmpfiles `z` activation).
{ lib, ... }:
{
  options = {
    # finix `modules/networking` omits `nameservers`; declared here for `infra.network`.
    networking.nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };

  # Finit's built-in `tmpfiles` ignores `z` (adjust mode/owner of existing paths) rules;
  # apply them during activation (after `users`) so both boot and `deploy` (`tar --owner=0`) stay consistent.
  config.system.activation.scripts.tmpfiles-z = {
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
