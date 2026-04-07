{
  fn,
  ctx,
  pkgs,
  ...
}:
let
  sb = ctx.services.sing-box;
  outTags = map (attr: attr.tag) sb.outbounds.shadowsocks;
  hy2Tags = map (attr: attr.tag) sb.outbounds.hysteria2;
in
{
  logicConfig = {
    outbounds = [
      {
        tag = "sele";
        type = "selector";
        outbounds = [
          "out"
          "hy2-out"
          "out-sele"
          "upstream"
        ];
        default = "out";
        interrupt_exist_connections = true;
      }
      {
        tag = "out";
        type = "urltest";
        outbounds = outTags;
        interval = "2m";
        interrupt_exist_connections = true;
      }
      {
        tag = "out-sele";
        type = "selector";
        outbounds = outTags;
        default = "out-us-lv";
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
        ++ outTags;
        default = "out";
      }
      {
        tag = "hy2-out";
        type = "selector";
        outbounds = hy2Tags;
        default = "hy2-us-lv";
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
          # no age verification
          domain_suffix = [
            "xvideos.com"
          ];
          outbound = "out-us-lv";
        }
        {
          domain_suffix = [
            "real-debrid.com"
          ];
          outbound = "direct";
        }
        {
          domain_suffix = [
            "strem.fun"
            "strem.io"
            "archive.org"
          ];
          outbound = "upstream";
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
          # obosolate usage for socks5 in torrent client
          port = 1080;
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
