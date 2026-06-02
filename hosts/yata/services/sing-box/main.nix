{
  pkgs,
  ctx,
  lib,
  global,
  ...
}:
let
  wg = ctx.services.wireguard;
in
{
  local.sing-box.settings = {
    log = {
      level = "debug";
      # redundant with systemd
      timestamp = false;
    };
    dns = {
      servers = [
        {
          tag = "bootstrap";
          type = "tls";
          server = "1.1.1.1";
          detour = "sele";
        }
        {
          tag = "tailscale";
          type = "udp";
          server = "${ctx.tailscale.ipv4}";
        }
      ];
      rules = [
        {
          domain_suffix = [
            global.domain.main
          ];
          server = "tailscale";
        }
        {
          # for some reason, they are unreachable through ipv6
          domain_suffix = [ "gnu.org" ];
          server = "bootstrap";
          strategy = "ipv4_only";
        }
      ];
      final = "bootstrap";
      strategy = "prefer_ipv6";
    };

    inbounds = [
      {
        tag = "hy2";
        type = "mixed";
        listen = "${wg.ipv4}";
        listen_port = 3080;
      }
      {
        type = "direct";
        tag = "wg-dns";
        network = "udp";
        listen = "${wg.ipv4}";
        listen_port = 53;
      }
    ];
    route = {
      default_domain_resolver = {
        server = "bootstrap";
        rewrite_ttl = 60;
      };
      rules = lib.mkBefore [
        {
          action = "sniff";
        }
        {
          protocol = "dns";
          action = "hijack-dns";
        }
        {
          action = "route-options";
          inbound = "wg-dns";
          override_address = "1.0.0.1";
          override_port = 53;
        }
      ];
    };
    outbounds = lib.mkOrder 100 [
      {
        tag = "direct";
        type = "direct";
      }
      {
        type = "socks";
        tag = "upstream";
        server = "127.0.0.1";
        server_port = 2080;
      }
    ];

    experimental = {
      clash_api = {
        external_controller = "127.0.0.1:9091";
        external_ui = "${pkgs.metacubexd}";
        secret._secret = ctx.services.sing-box.password.path;
      };
      cache_file = {
        enabled = true;
        # StateDirectory = /var/lib/sing-box should be used, base on nixpkgs
        path = "cache.db";
      };
    };
  };
}
