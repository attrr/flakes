{
  device,
  espSize ? "512M",
  imageSize ? "2G",
  home ? false,
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
  disko.devices.disk.main = {
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
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            subvolumes = {
              "@" = {
                mountpoint = "/";
                inherit mountOptions;
              };
              "@nix" = {
                mountpoint = "/nix";
                inherit mountOptions;
              };
            }
            // (
              if home then
                {
                  "@home" = {
                    mountpoint = "/home";
                    inherit mountOptions;
                  };
                }
              else
                { }
            );
          };
        };
      };
    };
  };
}
