{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        imageSize = "2G";
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02";
              priority = 1;
            };
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "cryptroot";
                passwordFile = "/tmp/password";
                settings.allowDiscards = true;
                extraOpenArgs = [ "--tpm2-device=auto" ];
                # Password is set via interactive prompt or file during build
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ]; # Force override if formatting an existing drive
                  subvolumes = {
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
