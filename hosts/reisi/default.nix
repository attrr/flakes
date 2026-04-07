{
  modulesPath,
  ctx,
  ...
}:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    (modulesPath + "/profiles/headless.nix")
    (modulesPath + "/profiles/minimal.nix")
    ../../modules/host/lowend
    ../../modules/ctx/proxy.nix
  ];

  boot.kernel.sysctl = {
    "net.ipv4.tcp_tw_reuse" = 1;
    "net.core.somaxconn" = 1024;
    "net.ipv4.tcp_fastopen" = 3;
  };

  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";

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
  services.tailscale.enable = true;

  cloud.server = {
    hostname = ctx.metadata.hostname;
    ssh-ports = ctx.ssh.ports;
    ssh-keys = ctx.ssh.auth-keys;
    auto-resize = true;
    zram-percent = 150;
  };

  core.server.sing-box = {
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
    };
    warp.lowend = true;
  };
}
