{
  modulesPath,
  ctx,
  self,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    self.modules.nixos.server
    ./fl-watch.nix
  ];

  infra.disko = {
    layout = "btrfs-subvol";
    device = "/dev/vda";
    espSize = "500M";
  };
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

  infra.server.lowend = true;
  zramSwap.memoryPercent = 150;

  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "150M";
    MemoryHigh = "120M";
  };

  infra.sing-box = {
    lowend = true;
    usque.ipv6 = true;
    settings = {
      route.rules = [
        {
          action = "sniff";
        }
        {
          # fixed-ip/direct for VPN restricted trackers
          domain_suffix = [
            "myanonamouse.net"
            "animebytes.tv"
            "gazellegames.net"
            "filelist.io"
          ];
          outbound = "direct";
        }
      ];
    };
  };
}
