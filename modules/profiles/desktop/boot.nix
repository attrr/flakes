# Fedora-like boot splash, quiet boot
{ pkgs, ... }:
{
  boot.plymouth = {
    enable = true;
    theme = "bgrt";
    font = "${pkgs.cantarell-fonts}/share/fonts/cantarell/Cantarell-VF.otf";
    extraConfig = "UseSimpledrmNoLuks=1";
  };
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "udev.log_level=3"
  ];
}
