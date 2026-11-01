{
  self,
  ctx,
  registry,
  ...
}:
{
  imports = [
    ./hardware.nix
    ./disko.nix
    ./bao.nix
  ];
  system.stateVersion = "25.11";
  boot.loader.grub.enable = true;

  core.server = {
    containers = false;
  };
  services.openssh.lockRootLogin = false;
  users.users.root.hashedPassword = ctx.ssh.hashed-password;
  services.tailscale.enable = true;

  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
  };
}
