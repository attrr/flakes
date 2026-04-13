{
  modulesPath,
  config,
  ctx,
  registry,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    ./disko.nix
    ./dns.nix
    ./librechat.nix
    ../../modules/host/server.nix
    ../../modules/ctx/proxy.nix
    ../../modules/purpose/acme.nix
  ];

  # Basics
  boot.loader.grub.enable = true;
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";

  cloud.server = {
    hostname = ctx.metadata.hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
    auto-resize = true;
  };

  # Networking
  networking.useNetworkd = true;
  systemd.network.networks."10-default" = {
    matchConfig.Name = "en*";
    networkConfig.DHCP = "ipv4";
    address = ctx.network.ipv6.cidr;
    routes = [ { Gateway = "fe80::1"; } ];
  };
  services.tailscale.enable = true;
  core.server.sing-box.uid = 994;

  core.acme = {
    enable = true;
    api = registry.acme-dns.url;
    certs."${ctx.metadata.fdqn}" = {
      domain = ctx.metadata.fdqn;
      extraDomainNames = [
        "*.${ctx.metadata.fdqn}"
      ];
    };
  };

  services.tailscale.extraSetFlags = [
    "--relay-server-port=${toString ctx.tailscale.relay-port}"
  ];

  networking.firewall = {
    allowedUDPPorts = [
      config.services.tailscale.port
      ctx.tailscale.relay-port
    ];
  };
}
