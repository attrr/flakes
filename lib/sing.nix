{ lib, ... }:
let
  normalize = lib.mapAttrs' (
    name: value: lib.nameValuePair (builtins.replaceStrings [ "-" ] [ "_" ] name) value
  );

  mapMergeEntries = default: map (value: lib.recursiveUpdate default (normalize value));
in
{
  inherit normalize;

  # -> tag, path
  mkLocalRuleSets = mapMergeEntries {
    type = "local";
    format = "binary";
  };

  # -> tag, server, server_port, password
  mkShadowsocks = mapMergeEntries {
    type = "shadowsocks";
    method = "2022-blake3-aes-128-gcm";
    multiplex = {
      enabled = true;
      protocol = "h2mux";
      max_streams = 32;
      padding = true;
    };
    detour = "upstream";
  };

  # -> tag, server, server_port, password, tls.*
  mkHysteria2 = mapMergeEntries {
    type = "hysteria2";
    up_mbps = 30;
    down_mbps = 100;
    tls = {
      enabled = true;
      alpn = [ "h3" ];
      ech.enabled = true;
    };
  };

  # -> tag, server, server_port, uuid, tls.*
  mkVless = mapMergeEntries {
    type = "vless";
    flow = "xtls-rprx-vision";
    packet_encoding = "xudp";
    tls = {
      enabled = true;
      reality.enabled = true;
      utls = {
        enabled = true;
        fingerprint = "chrome";
      };
    };
  };

  # _host_id, _prefixes, public_key, pre_shared_key
  mkWireGuardPeers = map (
    e:
    (removeAttrs e [
      "_host_id"
      "_prefixes"
    ])
    // {
      allowed_ips = map (
        prefix: "${prefix}${toString e._host_id}/${if lib.hasInfix ":" prefix then "128" else "32"}"
      ) e._prefixes;
    }
  );

  # _name, url
  mkProviders =
    l:
    mapMergeEntries
      {
        type = "http";
        # needs a `direct` entry in http_clients. By tag, not left to
        # route.default_http_client: the fork's providers resolve their client
        # before that one is set up
        http_client = "direct";
      }
      (
        map (
          e:
          (removeAttrs e [ "_name" ])
          // {
            tag = e._name;
            cache_file = "providers/${e._name}";
          }
        ) l
      );
}
