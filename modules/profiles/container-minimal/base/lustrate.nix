# First-boot takeover: sweep everything that is not Nix or container state.
# On overlayfs (Podman/Docker), delete swept entries (whiteouts, avoiding EXDEV full copies
# of lowerdir trees into `/old-root`); elsewhere, move them to `/old-root`.
{ config, lib, ... }:
let
  cfg = config.infra.container.lustrate;

  dest = dir: "/old-root${lib.removeSuffix "/" dir}";
  sweep = dir: keep: ''
    for d in ${lib.removeSuffix "/" dir}/*; do
      case "$d" in
        ${lib.concatMapStringsSep "|" (name: "${lib.removeSuffix "/" dir}/${name}") keep}) ;;
        *) sweep_entry "$d" ${dest dir} ;;
      esac
    done
  '';
in
{
  options.infra.container.lustrate.keep = lib.mkOption {
    type = with lib.types; attrsOf (listOf str);
    description = ''
      Directory -> entry names (shell globs) left in place by the first-boot lustrate.
      Every other entry of that directory is removed (on overlayfs) or moved to `/old-root`.
    '';
  };

  config = {
    infra.container.lustrate.keep = {
      "/" = [
        "nix"
        "sbin"
        "bin"
        "lib"
        "proc"
        "sys"
        "dev"
        "run"
        "tmp"
        "etc"
        "var"
        "old-root"
        "home"
        "root"
      ];
      "/etc" = [
        "NIXOS"
        "static"
        "hostname"
        "hosts"
        "resolv.conf"
        "ssh"
      ];
      "/etc/ssh" = [ "ssh_host_*" ];
      "/var" = [
        "lib"
        "log"
        "empty"
      ];
      "/var/lib" = [
        "secrets"
        "wrappers"
        "sing-box"
        "usque"
        "nixos"
      ];
    };

    # Directories are swept in path order, so parents run before children.
    system.activation.scripts.containerLustrate = ''
      if [ ! -L /etc/static ]; then
        is_overlay=0
        if awk '$2 == "/" { fs = $3 } END { exit (fs != "overlay") }' /proc/mounts 2>/dev/null; then
          is_overlay=1
        else
          mkdir -p ${lib.concatMapStringsSep " " dest (lib.attrNames cfg.keep)}
        fi

        sweep_entry() {
          if [ "$is_overlay" = 1 ]; then
            rm -rf "$1" 2>/dev/null || true
          else
            mv "$1" "$2/" 2>/dev/null || true
          fi
        }

        # Replace `/lib` and usr-merged `/sbin` with real init paths before sweeping `/usr`,
        # avoiding an init-less window if activation is interrupted (OOM / SIGKILL).
        if [ -e /lib ] || [ -L /lib ]; then
          if [ "$is_overlay" = 1 ] || [ -e /old-root/lib ] || [ -L /old-root/lib ]; then
            rm -rf /lib 2>/dev/null || true
          else
            mv /lib /old-root/ 2>/dev/null || rm -rf /lib 2>/dev/null || true
          fi
        fi
        [ -L /sbin ] && rm -f /sbin
        mkdir -p /sbin /lib/systemd
        ln -sfn "$systemConfig/init" /sbin/init
        ln -sfn "$systemConfig/init" /lib/systemd/systemd

        ${lib.concatStringsSep "\n" (lib.mapAttrsToList sweep cfg.keep)}

        # On usr-merged distros (Debian 12+, Ubuntu 22.04+, Arch, Fedora), `/bin -> usr/bin`
        # is now dangling after `/usr` is swept.
        if [ -L /bin ] && [ ! -e /bin ]; then
          rm -f /bin
        fi
        ${config.providers.bootloader.installHook} "$systemConfig"
      fi
    '';
    system.activation.scripts.binsh.deps = [ "containerLustrate" ];
    system.activation.scripts.etc.deps = [ "containerLustrate" ];
    system.activation.scripts.users.deps = [ "containerLustrate" ];
  };
}
