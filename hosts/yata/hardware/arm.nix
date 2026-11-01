{
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.kernelParams = [ "console=ttyS0,115200n8" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # no hardware watchdog: with sunxi-wdt at 15s (16s hw) and systemd petting
  # every ~6s the board still reset itself within the hour, twice

  hardware.deviceTree = {
    enable = true;
    name = "allwinner/sun50i-h618-orangepi-zero3.dtb";
  };
}
