# ABL -> U-Boot (pkgs/u-boot-google-flame, in boot_a/b) -> systemd-boot,
# from a GPT (4K sectors) written into the userdata partition
{
  config,
  lib,
  pkgs,
  ...
}:
{
  boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linux-qcom-sm8150;
  # the root's UFS is built in; the generic initrd modules are PCs' disks
  # and keyboards
  boot.initrd.includeDefaultModules = false;

  hardware.firmware = [ pkgs.firmware-google-flame ];

  # U-Boot's own dtb lacks the panel and touchscreen
  hardware.deviceTree = {
    enable = true;
    name = "qcom/sm8150-google-flame.dtb";
    # ramoops out of stock's carveout (0xa47ff000): on a reset, Google's ABL
    # encrypts it into the alt region beside it, with a key that Android's
    # vendor `ramoops` tool loads into the metadata page, and the plaintext
    # comes back wiped. Low RAM, away from ABL (0x9fc00000..) and from
    # U-Boot, the kernel and the initrd (all above 0x1c0000000); stock's
    # layout, without ftrace
    overlays = [
      {
        name = "flame-ramoops";
        filter = "sm8150-google-flame.dtb";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "google,floral-sm8150";
          };

          &{/reserved-memory/ramoops@a47ff000} {
            reg = <0x0 0xb0000000 0x0 0x200000>;
            no-map;
            record-size = <0x20000>;
            console-size = <0x100000>;
            ftrace-size = <0x0>;
            pmsg-size = <0x80000>;
          };
        '';
      }
    ];
  };

  # ABL counts down a slot's retries on every boot not marked successful, and
  # once out of them refuses it: every boot ends in fastboot until set_active.
  # Android's boot_control HAL marks it, pmOS uses qbootctl for that too
  systemd.services.mark-boot-successful = {
    description = "Mark the A/B slot's boot successful";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.qbootctl}/bin/qbootctl -m";
    };
  };

  boot.loader.systemd-boot = {
    enable = true;
    installDeviceTree = true;
    # a new U-Boot goes in as a capsule, which U-Boot applies to the active
    # boot slot (and deletes) on the next boot; ABL falls back to the other
    # slot if it doesn't come up. Only when the image changes: a new store
    # path alone isn't one, and it gets one with any kernel patch (its DT
    # is from the patched tree) or nixpkgs bump
    extraInstallCommands =
      let
        esp = config.boot.loader.efi.efiSysMountPoint;
        uboot = pkgs.u-boot-google-flame;
        hash = "${pkgs.coreutils}/bin/sha256sum";
      in
      ''
        new=$(${hash} < ${uboot}/u-boot.img)
        old=$(cat ${esp}/loader/u-boot 2>/dev/null)
        # the store path it used to be
        if [ -e "$old/u-boot.img" ]; then old=$(${hash} < "$old/u-boot.img"); fi
        if [ "$old" != "$new" ]; then
          mkdir -p ${esp}/EFI/UpdateCapsule
          cp ${uboot}/u-boot.capsule ${esp}/EFI/UpdateCapsule/u-boot.capsule
        fi
        echo "$new" > ${esp}/loader/u-boot
      '';
  };

  # no TPM, nor its modules
  systemd.tpm2.enable = false;
  boot.initrd.systemd = {
    enable = true;
    tpm2.enable = false;

    # the kernel doesn't scan a partition table inside a partition
    services.userdata-partitions = {
      description = "Partitions inside userdata";
      unitConfig.DefaultDependencies = false;
      requires = [ "dev-disk-by\\x2dpartlabel-userdata.device" ];
      after = [ "dev-disk-by\\x2dpartlabel-userdata.device" ];
      before = [ "initrd-root-device.target" ];
      wantedBy = [ "initrd-root-device.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${config.boot.initrd.systemd.package.util-linux}/bin/losetup --partscan --sector-size 4096 /dev/loop0 /dev/disk/by-partlabel/userdata";
      };
    };
    storePaths = [ "${config.boot.initrd.systemd.package.util-linux}/bin/losetup" ];

    # the image is smaller than userdata
    repart = {
      enable = true;
      device = "/dev/loop0";
    };
    services.systemd-repart = {
      requires = [ "userdata-partitions.service" ];
      after = [ "userdata-partitions.service" ];
    };
  };
  systemd.repart.partitions = {
    "10-esp" = {
      Type = "esp";
      Weight = 0;
    };
    "20-root".Type = "root-arm64";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/nixos";
    fsType = "ext4";
    autoResize = true;
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/esp";
    fsType = "vfat";
    options = [ "umask=0077" ];
  };

  # the firewall as it's been since pmOS's config, which had nftables but
  # not the xtables matches the iptables one uses
  networking.nftables.enable = lib.mkDefault true;
}
