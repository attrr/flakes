# First-boot takeover: move everything that is not Nix or container state into `/old-root`.
{ config, lib, ... }:
let
  cfg = config.infra.container.lustrate;

  dest = dir: "/old-root${lib.removeSuffix "/" dir}";
  sweep = dir: keep: ''
    for d in ${lib.removeSuffix "/" dir}/*; do
      case "$d" in
        ${lib.concatMapStringsSep "|" (name: "${lib.removeSuffix "/" dir}/${name}") keep}) ;;
        *) mv "$d" ${dest dir}/ 2>/dev/null || true ;;
      esac
    done
  '';
in
{
  options.infra.container.lustrate.keep = lib.mkOption {
    type = with lib.types; attrsOf (listOf str);
    description = ''
      Directory -> entry names (shell globs) left in place by the first-boot lustrate.
      Every other entry of that directory moves to the same path under `/old-root`.
    '';
  };

  config = {
    infra.container.lustrate.keep = {
      "/" = [
        "nix"
        "sbin"
        "bin"
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
        mkdir -p ${lib.concatMapStringsSep " " dest (lib.attrNames cfg.keep)}
        ${lib.concatStringsSep "\n" (lib.mapAttrsToList sweep cfg.keep)}
      fi
    '';
    system.activation.scripts.etc.deps = [ "containerLustrate" ];
    system.activation.scripts.users.deps = [ "containerLustrate" ];
  };
}
