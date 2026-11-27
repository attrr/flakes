{ config, lib, ... }:
let
  cfg = config.boot.serial;
  sdboot = config.boot.loader.systemd-boot.enable;
  grub = config.boot.loader.grub.enable;
in
{
  options.boot.serial = {
    enable = lib.mkEnableOption "serial console";
    device = lib.mkOption {
      type = lib.types.str;
      default = "ttyS0";
      description = "Serial console device name.";
    };
    baud = lib.mkOption {
      type = lib.types.int;
      default = 115200;
      description = "Serial console baud rate.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelParams = [
      "console=${cfg.device},${toString cfg.baud}n8"
      "console=tty1"
    ]
    ++ lib.optional (cfg.device == "ttyS0") "earlycon=uart8250,io,0x3f8,${toString cfg.baud}n8";

    boot.loader.systemd-boot.consoleMode = lib.mkIf sdboot "auto";
    boot.loader.grub.extraConfig = lib.mkIf grub ''
      serial --speed=${toString cfg.baud} --unit=0 --word=8 --parity=no --stop=1
      terminal_input serial
      terminal_output serial
    '';

    # override headless.nix
    systemd.services."serial-getty@${cfg.device}".enable = true;
  };
}
