# stage1 — the rescue OS itself: a systemd initrd that never leaves initrd,
# with sshd, a console shell and enough tools to dd/partition a disk.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  cfg = config.rescue;
in
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/minimal.nix")
  ];

  options.rescue = {
    ssh = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 22;
      };
      authorizedKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "root keys; more can be passed at boot via ssh_key= on the cmdline";
      };
      hostKeys = lib.mkOption {
        type = lib.types.listOf lib.types.path;
        default = [ ];
        description = "generated at boot when empty";
      };
    };
    zram = {
      enable = lib.mkEnableOption "zram swap";
      size = lib.mkOption {
        type = lib.types.str;
        default = "80M";
      };
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
    };
  };

  config = {
    # boot.initrd.network.ssh.hostKeys fails with grub enabled
    boot.loader.grub.enable = false;
    boot.kernelParams = [
      "console=ttyS0"
      "console=tty0"
      "panic=30"
    ];
    boot.kernel.sysctl."vm.overcommit_memory" = "1";

    boot.initrd.systemd = {
      enable = true;
      emergencyAccess = true;

      # stay in initrd
      services = {
        initrd-find-nixos-closure.enable = false;
        initrd-nixos-activation.enable = false;
        initrd-cleanup.enable = false;
        initrd-parse-etc.enable = false;
        initrd-switch-root.enable = false;
      };

      network.enable = true;
      network.networks."99-eth-all" = {
        matchConfig.Name = lib.mkDefault "en* eth*";
        networkConfig.DHCP = lib.mkDefault "yes";
      };

      initrdBin =
        with pkgs;
        [
          util-linux
          busybox
          zstd
          zsh
          grub2
          iproute2
          parted
          curl
          htop
          openssh
        ]
        ++ cfg.extraPackages;
    };

    # ssh
    boot.initrd.network.ssh = {
      enable = true;
      inherit (cfg.ssh) port authorizedKeys hostKeys;
      shell = "/bin/zsh";
    };
    boot.initrd.systemd.services.ssh-key-injection = {
      description = "Inject SSH keys from cmdline and generate host key";
      wantedBy = [
        "sshd.service"
        "initrd.target"
      ];
      before = [ "sshd.service" ];
      after = [ "initrd-nixos-copy-secrets.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      # root's home is /var/empty here, so keys go where sshd_config looks
      script = ''
        keys=/etc/ssh/authorized_keys.d/root
        mkdir -p /etc/ssh/authorized_keys.d

        if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
          ssh-keygen -t ed25519 -N "" -f /etc/ssh/ssh_host_ed25519_key
        fi

        # may be a read-only store symlink
        { cat "$keys" 2>/dev/null; } > "$keys.new"
        eval "set -- $(cat /proc/cmdline)"
        for arg do
          case "$arg" in
            ssh_key=*) echo "''${arg#ssh_key=}" >> "$keys.new" ;;
          esac
        done
        chmod 644 "$keys.new"
        mv -f "$keys.new" "$keys"
      '';
    };

    # a zsh on every console= tty (ttyS0 + tty0 if none given)
    boot.initrd.systemd.services."console-shell@" = {
      description = "Console shell on %I";
      serviceConfig = {
        StandardInput = "tty";
        StandardOutput = "tty";
        StandardError = "tty";
        TTYPath = "/dev/%I";
        ExecStart = "${pkgs.zsh}/bin/zsh";
        Restart = "always";
      };
      unitConfig.DefaultDependencies = false;
    };
    boot.initrd.systemd.storePaths = [
      pkgs.zsh
      pkgs.grml-zsh-config
    ];
    boot.initrd.systemd.contents = {
      "/etc/systemd/system-generators/console-generator".source =
        pkgs.writeShellScript "console-generator" (builtins.readFile ./console.sh);
      "/usr/share/terminfo".source = "${pkgs.ncurses}/share/terminfo";
      "/etc/zshrc".text = ''
        source ${pkgs.grml-zsh-config}/etc/zsh/zshrc
        export TERM=''${TERM:-linux}
        export TERMINFO_DIRS=/usr/share/terminfo
        export SYSTEMD_COLORS=1
        export PATH=/bin
        PS1='[rescue@${config.networking.hostName}:%~]%# '
      '';
    };

    # zram
    boot.initrd.availableKernelModules = lib.mkIf cfg.zram.enable [ "zram" ];
    boot.initrd.systemd.services.zram = lib.mkIf cfg.zram.enable {
      description = "zram swap";
      wantedBy = [ "initrd.target" ];
      before = [ "swap.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        modprobe zram
        echo lz4 > /sys/class/block/zram0/comp_algorithm
        echo ${cfg.zram.size} > /sys/class/block/zram0/disksize
        mkswap /dev/zram0
        swapon -p 50 /dev/zram0
      '';
    };

    system.stateVersion = lib.trivial.release;
  };
}
