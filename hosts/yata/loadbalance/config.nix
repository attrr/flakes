{
  pkgs,
  ctx,
  fn,
  lib,
  ...
}:
let
  lb = ctx.services.loadbalance;
in
{
  infra.loadbalance.settings = {
    log = {
      level = "debug";
      timestamp = false;
    };
    dns = {
      servers = [
        {
          tag = "bootstrap";
          type = "https";
          server = "223.5.5.5";
        }
        {
          tag = "local";
          type = "https";
          server = "1.1.1.1";
          detour = "auto";
        }
      ];
      rules = [
        {
          rule_set = [ "geosite:cn" ];
          server = "bootstrap";
        }
        {
          rule_set = [ "geosite:gfw" ];
          server = "local";
        }
      ];
      final = "local";
      strategy = "prefer_ipv4";
    };
    inbounds = [
      {
        tag = "in";
        type = "mixed";
        listen = "0.0.0.0";
        listen_port = 2080;
      }
      {
        tag = "select";
        type = "mixed";
        listen = "0.0.0.0";
        listen_port = 2088;
      }
    ];
    outbounds = lib.mkBefore [
      {
        type = "direct";
        tag = "direct";
      }
    ];
    route = {
      default_domain_resolver = {
        server = "bootstrap";
        rewrite_ttl = 60;
      };
      rule_set = fn.sing.mkLocalRuleSets [
        {
          tag = "geosite:cn";
          path = "${pkgs.sing-geosite}/share/sing-box/rule-set/geosite-cn.srs";
        }
        {
          tag = "geoip:cn";
          path = "${pkgs.sing-geoip}/share/sing-box/rule-set/geoip-cn.srs";
        }
        {
          tag = "geosite:gfw";
          path = "${pkgs.sing-geosite}/share/sing-box/rule-set/geosite-geolocation-!cn.srs";
        }
      ];
      rules = [
        {
          action = "sniff";
        }
        {
          protocol = "dns";
          action = "hijack-dns";
        }
        {
          inbound = "in";
          outbound = "auto";
        }
        {
          inbound = "select";
          outbound = "select";
        }
        {
          rule_set = [
            "geosite:cn"
            "geoip:cn"
          ];
          outbound = "direct";
        }
        {
          action = "reject";
          method = "drop";
        }
      ];
    };
    experimental = {
      clash_api = {
        external_controller = "127.0.0.1:9090";
        external_ui = "${pkgs.metacubexd}";
        secret._secret = "${lb.password.path}";
      };
      cache_file = {
        enabled = true;
        path = "cache.db";
      };
    };
  };

  infra.loadbalance.secrets = [
    lb.password.path
  ];
}
