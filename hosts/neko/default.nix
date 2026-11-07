{
  lib,
  pkgs,
  self,
  ...
}:
{
  imports = [
    "${self}/modules/hardware/kled.nix"
    ./hardware.nix
    ./disko.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  fonts.packages = [ pkgs.font-awesome ];

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # hp and epson drivers
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "hplip"
      "iscan"
      "iscan-ds"
      "iscan-data"
      "iscan-v330-bundle"
      "iscan-gt"
      "iscan-gt-f720-bundle"
      "iscan-nt-bundle"
      "iscan-gt-s600-bundle"
      "iscan-gt-s650-bundle"
      "iscan-gt-s80-bundle"
      "iscan-gt-x820-bundle"
      "iscan-gt-x750-bundle"
      "iscan-gt-x770-bundle"
      "iscan-v370-bundle"
      "iscan-perfection-v550-bundle"
    ];
  services.printing = {
    # run on first setup: sudo hp-setup -i -a
    drivers = [ pkgs.hplipWithPlugin ];
  };
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.epkowa ];
  };
  users.users.foo.extraGroups = [
    "lp"
    "scanner"
  ];

  programs.ssh.enableAskPassword = false;
  security.sudo.wheelNeedsPassword = false;
  system.stateVersion = "25.11";

}
