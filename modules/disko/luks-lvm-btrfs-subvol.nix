{
  device,
  imageSize ? "2G",
  espSize ? "1024M",
  swapSize ? null,
  luksName ? "cryptroot",
  vgName ? "nixos",
  compress ? true,
}:
let
  mountOptions = [
    "noatime"
    "discard=async"
  ]
  ++ (if compress then [ "compress=zstd" ] else [ ]);
in
{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = device;
      imageSize = imageSize;
      content = {
        type = "gpt";
        partitions = {
          boot = {
            size = "1M";
            type = "EF02";
            priority = 1;
          };
          ESP = {
            size = espSize;
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
              name = luksName;
              settings.allowDiscards = true;
              content = {
                type = "lvm_pv";
                vg = vgName;
              };
            };
          };
        };
      };
    };

    lvm_vg.${vgName} = {
      type = "lvm_vg";
      lvs =
        (
          if (swapSize != null) then
            {
              swap = {
                size = swapSize;
                content = {
                  type = "swap";
                  resumeDevice = true;
                };
              };
            }
          else
            { }
        )
        // {
          root = {
            size = "100%FREE";
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes = {
                "@" = {
                  mountpoint = "/";
                  inherit mountOptions;
                };
                "@home" = {
                  mountpoint = "/home";
                  inherit mountOptions;
                };
                "@nix" = {
                  mountpoint = "/nix";
                  inherit mountOptions;
                };
              };
            };
          };
        };
    };
  };
}
