{
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;
  boot.kernelParams = [ "console=ttyS0,115200n8" ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "ext4";
  };

  # H618 hardware watchdog: reboots the board when pid 1 stops petting it.
  # sunxi-wdt can't go above 16s; loaded in initrd so systemd finds it at start
  boot.initrd.kernelModules = [ "sunxi_wdt" ];
  systemd.settings.Manager = {
    RuntimeWatchdogSec = "15s";
    # a reboot that hangs (stuck unmount on the sd card) still goes through
    RebootWatchdogSec = "2min";
  };

  hardware.deviceTree = {
    enable = true;
    name = "allwinner/sun50i-h618-orangepi-zero3.dtb";
  };
}
