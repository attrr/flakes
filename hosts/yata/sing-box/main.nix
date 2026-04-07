{
  pkgs,
  ctx,
  global,
  ...
}:
let
  wg = ctx.services.wireguard;
in
{
  mainConfig = {
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
        sniff = true;
        sniff_override_destination = false;
      }
      {
        type = "direct";
        tag = "wg-dns";
        network = "udp";
        listen = "${wg.ipv4}";
        listen_port = 53;
        override_address = "1.0.0.1";
        override_port = 53;
      }
    ];
    outbounds = [
      {
        tag = "direct";
        type = "direct";
      }
      {
        tag = "block";
        type = "block";
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
        secret = ctx.services.sing-box.password.ph;
      };
      cache_file = {
        enabled = true;
        # StateDirectory = /var/lib/sing-box should be used, base on nixpkgs
        path = "cache.db";
      };
    };
  };
}
