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
    ./dns.nix
    ./librechat.nix
    ./wiki.nix
  ];

  infra.disko = {
    layout = "ext4-plain";
    device = "/dev/sda";
  };

  # Basics
  boot.loader.grub.enable = true;
  system.stateVersion = "25.11";

  infra.server = {
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
  infra.sing-box.uid = 994;

  infra.acme = {
    enable = true;
    api = registry.acme-dns.url;
    certs."${ctx.metadata.fdqn}" = {
      domain = ctx.metadata.fdqn;
      extraDomainNames = [
        "*.${ctx.metadata.fdqn}"
      ];
    };
  };

  infra.restic =
    let
      restic = ctx.services.restic;
    in
    {
      enable = true;
      s3.bucketName = restic.bucket-name;
      environmentFile = restic.env.path;
      passwordFile = restic.password.path;

      backups.infra = {
        paths = [
          "/var/lib/acme"
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
