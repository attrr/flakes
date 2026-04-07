{
  ctx,
  registry,
  ...
}:
{
  imports = [
    ../../modules/host/server.nix
    ../../modules/purpose/acme.nix
    ./hardware.nix
    ./disko.nix
    ./bao.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";

  cloud.server = {
    hostname = ctx.metadata.hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
    containers = false;
  };
  services.openssh.lockRootLogin = false;
  users.users.root.hashedPassword = ctx.ssh.hashed-password;
  services.tailscale.enable = true;

  core.acme = {
    enable = true;
    api = registry.acme-dns.url;
  };
}
