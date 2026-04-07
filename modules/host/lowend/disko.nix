{ lib, config, ... }:
let
  cfg = config.cloud.server.disko;
in
{
  options.cloud.server.disko = {
    efi = lib.mkEnableOption "boot mode";
    device = lib.mkOption {
      type = lib.types.str;
      default = "/dev/vda";
    };
    image-size = lib.mkOption {
      type = lib.types.str;
      default = "2G";
    };
  };

  config = {
    # bootloaders
    boot.loader.systemd-boot.enable = lib.mkIf cfg.efi true;
    boot.loader.efi.canTouchEfiVariables = lib.mkIf cfg.efi true;
    boot.loader.grub.enable = lib.mkIf (!cfg.efi) true;

    disko.devices = {
      disk = {
        main = {
          type = "disk";
          imageSize = "${cfg.image-size}";
          device = "${cfg.device}";
          content = {
            type = "gpt";
            partitions = {
              boot = {
                size = "1M";
                type = "EF02"; # For GRUB MBR fallback
                priority = 1; # Needs to be first partition
              };
              ESP = {
                size = "500M";
                type = "EF00";
                content = {
                  type = "filesystem";
                  format = "vfat";
                  mountpoint = "/boot";
                  mountOptions = [ "umask=0077" ];
                };
              };
              root = {
                size = "100%";
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ]; # Force override if formatting an existing drive
                  subvolumes = {
                    # The root subvolume with ZSTD forced on
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = [
                        "compress-force=zstd"
                        "noatime"
                        "discard=async"
                      ];
                    };
                    # Isolating the Nix store
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = [
                        "compress-force=zstd"
                        "noatime"
                        "discard=async"
                      ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}
