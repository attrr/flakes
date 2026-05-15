{
  self,
  ctx,
  registry,
  ...
}:
{
  imports = [
    "${self}/modules/host/server.nix"
    "${self}/modules/purpose/acme.nix"
    ./hardware.nix
    ./disko.nix
    ./bao.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";
  boot.loader.grub = true;

  core.server = {
    hostname = ctx.metadata.hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
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
