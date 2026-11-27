{
  includes = [ ../profiles/server ];

  ctx.nixos =
    {
      lib,
      ctx,
      modulesPath,
      ...
    }:
    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      infra.disko = {
        layout = "btrfs-subvol";
        device = "/dev/sda";
        espSize = "1G";
        imageSize = "6G";
      };
      system.stateVersion = "26.05";

      boot.serial.enable = lib.mkDefault (ctx.metadata.arch == "x86_64-linux");

      boot.loader.efi.canTouchEfiVariables = true;
      boot.loader.systemd-boot.enable = true;

      infra.network.topology = "dhcp";
      services.tailscale.enable = true;
    };
}
