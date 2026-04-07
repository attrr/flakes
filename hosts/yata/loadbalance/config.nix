{
  pkgs,
  ctx,
  fn,
  lib,
  ...
}:
let
  lb = ctx.services.loadbalance;
  ctxToSing = n: v: v // { url = v.url.ph; _name = n;} ;
  providers = builtins.attrNames lb.providers;
in
{
  providerConfig = {
    providers = fn.sing.mkProviders (lib.mapAttrsToList ctxToSing lb.providers);
    outbounds = [
      {
        type = "selector";
        tag = "select";
        providers = providers;
      }
      {
        type = "loadbalance";
        tag = "auto";
        providers = providers;
        check = {
          interval = "2m";
        };
        pick = {
          objective = "leastload";
          strategy = "random";
          max_fail = 0;
          max_rtt = "3000ms";
          expected = 3;
          baselines = [
            "30ms"
            "50ms"
            "100ms"
            "150ms"
            "200ms"
            "250ms"
            "350ms"
          ];
        };
      }
    ];
  };

  mainConfig = {
    log = {
      level = "debug";
      timestamp = false;
    };
    dns = {
      servers = [
        {
          tag = "bootstrap";
          address = "https://223.5.5.5/dns-query";
          detour = "direct";
        }
        {
          tag = "local";
          address = "https://1.1.1.1/dns-query";
          detour = "auto";
        }
      ];
      rules = [
        {
          outbound = [
            "any"
            "direct"
          ];
          server = "bootstrap";
        }
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
    outbounds = [
      {
        type = "block";
        tag = "block";
      }
      {
        type = "direct";
        tag = "direct";
      }
    ];
    route = {
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
      ];
      final = "block";
    };
    experimental = {
      clash_api = {
        external_controller = "127.0.0.1:9090";
        external_ui = "${pkgs.metacubexd}";
        secret = "${lb.password.ph}";
      };
      cache_file = {
        enabled = true;
        # StateDirectory = /var/lib/sing-box should be used, base on nixpkgs
        path = "cache.db";
      };
    };
  };
}
