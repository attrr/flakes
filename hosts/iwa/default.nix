{
  ctx,
  registry,
  self,
  ...
}:
{
  imports = [
    self.modules.nixos.server
    ./hardware.nix
  ];

  system.stateVersion = "25.11";
  boot.loader.grub.enable = true;

  infra.disko = {
    layout = "btrfs-subvol";
    device = "/dev/sda";
    espSize = "512M";
  };

  infra.containers.enable = false;

  users.mutableUsers = false;
  users.users.root.hashedPassword = ctx.ssh.hashed-password;
  services.openssh.lockRootLogin = false;

  services.tailscale.enable = true;
  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
  };
}
