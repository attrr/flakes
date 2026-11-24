{
  lib,
  pkgs,
  self,
  ...
}:
{
  imports = [
    self.modules.nixos.desktop
    "${self}/modules/hardware/kled.nix"
    ./hardware.nix
  ];

  infra.disko = {
    layout = "luks-lvm-btrfs-subvol";
    device = "/dev/nvme0n1";
    espSize = "1G";
    extraArgs = {
      luksName = "env";
      swapSize = "16G";
    };
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fonts.packages = [ pkgs.font-awesome ];

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  infra.desktop.printing = {
    hp = true;
    epson = true;
  };

  programs.ssh.enableAskPassword = false;
  security.sudo.wheelNeedsPassword = false;
  system.stateVersion = "25.11";

}
