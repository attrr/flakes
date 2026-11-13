{
  ctx,
  registry,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./dns.nix
  ];
  system.stateVersion = "25.11";
  boot.loader.grub.enable = true;

  infra.disko = {
    layout = "btrfs-subvol";
    device = "/dev/sda";
    espSize = "512M";
  };

  infra.server = {
    containers = false;
    auto-resize = true;
  };
  services.openssh.lockRootLogin = false;
  users.users.root.hashedPassword = ctx.ssh.hashed-password;
  services.tailscale.enable = true;

  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
  };
}
