{
  fn,
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.local.sing-box;
  tags = cfg.tags;
in
{
  local.sing-box.settings = {
    outbounds = lib.mkOrder 200 [
      {
        tag = "sele";
        type = "selector";
        outbounds = [
          "out"
          "out-all"
          "hy2-out"
          "upstream"
        ];
        default = "out";
        interrupt_exist_connections = true;
      }
      {
        tag = "out";
        type = "urltest";
        outbounds = tags.shadowsocks;
        interval = "2m";
        interrupt_exist_connections = true;
      }
      {
        tag = "out-all";
        type = "selector";
        outbounds = tags.shadowsocks ++ tags.hysteria2 ++ tags.vless;
        interrupt_exist_connections = true;
      }
      {
        tag = "ssh";
        type = "selector";
        outbounds = [
          "out"
          "hy2-out"
        ];
        default = "out";
      }
      {
        tag = "trackers";
        type = "selector";
        outbounds = [
          "out"
          "direct"
        ]
        ++ tags.shadowsocks;
        default = "out";
      }
      {
        tag = "hy2-out";
        type = "selector";
        outbounds = tags.hysteria2;
        interrupt_exist_connections = true;
      }
    ];

    route = {
      rule_set = fn.sing.mkLocalRuleSets [
        {
          tag = "geosite:google";
          path = "${pkgs.sing-geosite}/share/sing-box/rule-set/geosite-google.srs";
        }
        {
          tag = "geosite:ehentai";
          path = "${pkgs.sing-geosite}/share/sing-box/rule-set/geosite-ehentai.srs";
        }
        {
          tag = "geosite:cn";
          path = "${pkgs.sing-geosite}/share/sing-box/rule-set/geosite-cn.srs";
        }
        {
          tag = "geoip:cn";
          path = "${pkgs.sing-geoip}/share/sing-box/rule-set/geoip-cn.srs";
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
          inbound = "hy2";
          outbound = "hy2-out";
        }
        {
          # forwarding between peers
          ip_cidr = [
            "10.0.0.0/24"
            "2001:470:1f0f:15::/64"
          ];
          outbound = "wg";
        }
        {
          # tailscale
          ip_cidr = [
            "100.64.0.0/10"
            "fd7a:115c:a1e0::/48"
          ];
          outbound = "direct";
        }
        {
          # fixed-ip/direct for VPN restricted trackers
          domain_suffix = [
            "animebytes.tv"
            "gazellegames.net"
          ];
          outbound = "trackers";
        }
        {
          domain_suffix = [
            "real-debrid.com"
            "torbox.app"
            "tb-cdn.st"
            "tb-cdn.pw"
            "strem.fun"
          ];
          outbound = "direct";
        }
        {
          # high volume traffic
          domain_suffix = [
            "easynews.com"
            "news.eweka.nl"
          ];
          outbound = "hy2-out";
        }
        {
          # dot has to out
          port = 853;
          outbound = "out";
        }
      ];
      final = "sele";
    };
  };
}
