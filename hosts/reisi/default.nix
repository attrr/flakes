{
  self,
  modulesPath,
  ctx,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    (modulesPath + "/profiles/minimal.nix")
    (import "${self}/modules/disko/btrfs-subvol-deprecated.nix" {
      device = "/dev/vda";
      espSize = "500M";
    })
    "${self}/modules/profiles/server"
    "${self}/modules/ctx/proxy.nix"
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";
  boot.loader.grub.enable = true;

  # Networking
  networking.useNetworkd = true;
  systemd.network = {
    networks."20-default" = {
      matchConfig.Name = "e*";
      networkConfig = {
        DHCP = "ipv4";
        KeepConfiguration = "static";
      };
      address = ctx.network.ipv4.cidr ++ ctx.network.ipv6.cidr;
      dhcpV4Config = {
        RouteMetric = 10;
      };
      routes = [
        {
          Gateway = ctx.network.ipv4.gateway;
          Metric = 100;
        }
        {
          Gateway = ctx.network.ipv6.gateway;
          GatewayOnLink = true;
        }
      ];
    };
  };

  core.server.lowend.is = true;
  core.server.lowend.zram-percent = 150;
  core.server = {
    hostname = ctx.metadata.hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
    auto-resize = true;
  };

  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "150M";
    MemoryHigh = "120M";
  };

  infra.sing-box = {
    lowend = true;
    settings = {
      route.rules = [
        {
          action = "sniff";
        }
        {
          # fixed-ip/direct for VPN restricted trackers
          domain_suffix = [
            "animebytes.tv"
            "gazellegames.net"
          ];
          outbound = "direct";
        }
      ];
      log.level = "debug";
    };
  };
}
