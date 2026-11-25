let
  mkInstallInit =
    {
      lib,
      pkgs,
      sh,
      paths,
    }:
    let
      dirs = lib.unique (map dirOf paths);
    in
    pkgs.writeScript "container-bootloader" ''
      #!${sh}
      mkdir -p ${lib.concatStringsSep " " dirs}
      ${lib.concatMapStringsSep "\n" (p: ''ln -sfn "$1/init" ${p}'') paths}
    '';
in
{
  common =
    { lib, ... }:
    {
      options.infra.container = {
        initPaths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "/sbin/init"
            "/lib/systemd/systemd"
            "/usr/sbin/init"
            "/usr/lib/systemd/systemd"
          ];
          description = "Init entrypoint paths symlinked to `$systemConfig/init` on container activation.";
        };

        installInit = lib.mkOption {
          type = lib.types.package;
          internal = true;
          description = "Script that creates `initPaths` symlinks pointing at `$1/init`.";
        };
      };
    };

  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      infra.container.installInit = mkInstallInit {
        inherit lib pkgs;
        sh = pkgs.runtimeShell;
        paths = config.infra.container.initPaths;
      };

      system.activationScripts.containerInit = {
        deps = [ "containerLustrate" ];
        text = ''
          mkdir -p /bin
          ln -sfn ${pkgs.bashInteractive}/bin/bash /bin/bash
          ${config.infra.container.installInit} "$systemConfig"
        '';
      };
    };

  finix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.infra.container;
      coreutils = config.programs.coreutils.package;
    in
    {
      infra.container.installInit = mkInstallInit {
        inherit lib pkgs;
        sh = "${coreutils}/bin/sh";
        paths = cfg.initPaths;
      };

      providers.bootloader.installHook = cfg.installInit;

      # Container runtimes invoke `/sbin/init`, so `argv[0]` would be `/sbin/init` and `finix-setup`
      # would set `/run/current-system -> /sbin`. Use `bash`'s `exec -a` to pass `$sys/init` as `argv[0]`.
      boot.init = lib.mkDefault (
        pkgs.writeScript "init" ''
          #!${config.programs.bash.package}/bin/bash
          sys=$(${coreutils}/bin/readlink -f /nix/var/nix/profiles/system)
          ${coreutils}/bin/mkdir -p /run

          # Finit's `bootmisc` cleans non-tmpfs `/run` with `nftw()` without `FTW_PHYS`,
          # which follows symlinks and wipes `/nix/store/...-finix-system` or `/var/lib/*`!
          if ! ${coreutils}/bin/mountpoint -q /run; then
            ${coreutils}/bin/mount -t tmpfs -o mode=0755,nosuid,nodev tmpfs /run 2>/dev/null \
              || ${coreutils}/bin/rm -f /run/current-system /run/booted-system /run/secrets /run/wrappers
          fi

          exec -a "$sys/init" ${config.finit.package}/bin/finit "$@"
        ''
      );

      # Container bootstrap & takeover script run during `$toplevel/activate`.
      system.activation.scripts.containerInit = {
        deps = [
          "containerLustrate"
          "specialfs"
          "users"
          "etc"
        ];
        text = ''
          touch /etc/NIXOS

          if [ ! -e /nix/var/nix/profiles/system ]; then
            ln -sfn "$systemConfig" /nix/var/nix/profiles/system
          fi

          # Provider web consoles and `podman/lxc exec` often invoke `/bin/bash` directly.
          mkdir -p /bin
          ln -sfn /run/current-system/sw/bin/bash /bin/bash
          ${config.providers.bootloader.installHook} "$systemConfig"
        '';
      };
    };
}
