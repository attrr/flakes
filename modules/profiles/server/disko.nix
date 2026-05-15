{ lib, config, ... }:
let
  cfg = config.core.server.disko;
in
{
  options.core.server.disko = {
    efi = lib.mkEnableOption "boot mode";
  };

  config = {
    # bootloaders
    boot.loader.systemd-boot.enable = lib.mkIf cfg.efi true;
    boot.loader.efi.canTouchEfiVariables = lib.mkIf cfg.efi true;
    boot.loader.grub.enable = lib.mkIf (!cfg.efi) true;
  };
}
