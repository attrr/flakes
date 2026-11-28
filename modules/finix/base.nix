{
  config,
  finix,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  baseFinit = pkgs.callPackage "${inputs.nixpkgs-unstable}/pkgs/by-name/fi/finit/package.nix" { };
in
{
  options.infra.finix.legacyInotify = lib.mkEnableOption "strip IN_MASK_CREATE from finit for kernels older than Linux 4.18 (e.g. OpenVZ 7 / 3.10)";

  imports = [
    "${finix}/modules/lib"
    "${finix}/modules/misc"
    "${finix}/modules/environment"
    "${finix}/modules/users"
    "${finix}/modules/nixos/ids.nix"
    "${finix}/modules/nixos/ca.nix"
    "${finix}/modules/programs/coreutils"
    "${finix}/modules/programs/sh"
    "${finix}/modules/programs/bash"
    "${finix}/modules/programs/shadow"
    "${finix}/modules/programs/sudo"
    "${finix}/modules/programs/ifupdown-ng"
    "${finix}/modules/services/openssh"
    "${finix}/modules/security"
    "${finix}/modules/time"
    "${finix}/modules/networking"
    "${finix}/modules/providers/bootloader"
    "${finix}/modules/providers/firewall"
    "${finix}/modules/providers/privileges"
    "${finix}/modules/providers/scheduler"
    "${finix}/modules/services/cron"
    "${finix}/modules/services/nftables"
    "${finix}/modules/services/sysklogd"
    "${finix}/modules/system/activation"
    "${finix}/modules/system/activation/specialisation.nix"
    "${finix}/modules/system/activation/switchable-system.nix"
    "${finix}/modules/system/nixos-compat.nix"
    "${finix}/modules/finit"
    "${inputs.nixpkgs}/nixos/modules/misc/nixpkgs.nix"
    "${inputs.nixpkgs}/nixos/modules/programs/htop.nix"
  ];

  disabledModules = [
    "${finix}/modules/finit/initrd.nix"
    "${finix}/modules/finit/mount.nix"
    "${inputs.nixpkgs}/nixos/modules/misc/assertions.nix"
  ];

  config = lib.mkMerge [
    {
      # finix's libconfuse finit.conf format requires finit >= 5.0; build unstable's derivation
      # against this system's pkgs so glibc/util-linux are not duplicated.
      finit.package = lib.mkDefault (
        if config.infra.finix.legacyInotify then
          baseFinit.overrideAttrs (old: {
            postPatch = (old.postPatch or "") + ''
              substituteInPlace src/iwatch.h \
                --replace-fail ' | IN_MASK_CREATE' ""
            '';
          })
        else
          baseFinit
      );
      # Satisfy finit's non-empty ttys assertion without spawning a getty in containers.
      finit.ttys.console = {
        enable = false;
        device = "@console";
      };
      # Finit drops into `sulogin` if `/etc/fstab` is missing.
      environment.etc.fstab.text = lib.mkDefault "";
      # Ensure `/run/secrets` and `/run/wrappers` exist before runlevel 2 services start.
      finit.tasks.tmpfiles-setup.runlevel = "S";
    }
    (lib.mkIf config.programs.ifupdown-ng.enable {
      finit.tmpfiles.rules = [ "d /run/network 0755 - -" ];
    })
  ];
}
