{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/nvme0n1";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          type = "EF00";
          size = "1624M";
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
            name = "root";
            settings.allowDiscards = true;
            content = {
              type = "btrfs";
              extraArgs = [ "-f" ];
              subvolumes =
                let
                  mountOptions = [
                    "compress=zstd"
                    "noatime"
                    "discard=async"
                  ];
                in
                {
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
                  # Fedora's root, not mounted here
                  "@fedora" = { };
                };
            };
          };
        };
      };
    };
  };
}
