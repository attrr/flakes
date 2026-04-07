{ lib, ... }:
let
  normalize = set: 
    lib.mapAttrs' (name: value: 
      lib.nameValuePair (builtins.replaceStrings ["-"] ["_"] name) value
    ) set;

  # Attr, Attr -> Attr
  mapMergeAttrs = default: value: lib.recursiveUpdate default (normalize value);
  # Attr, Entries -> Entries
  mapMergeEntries = default: l: map (mapMergeAttrs default) l;
  # ((n, v) -> bool), Entries -> { _true = Entries, _false=Entries }
  splitEntries = pred: entries: {
    _true = map (lib.filterAttrs pred) entries;
    _false = map (lib.filterAttrs (n: v: !(pred n v))) entries;
  };
  # ((n, v) -> bool), Entries -> Entries
  splitWithPrefixEntries = prefix: entries: splitEntries (n: v: lib.hasPrefix prefix n) entries;
  # Entries, Entries = Entries
  combineEntries = lib.zipListsWith lib.recursiveUpdate;
in
{
  inherit normalize;
  # -> tag, path
  mkRemoteRulesets = mapMergeEntries {
    type = "remote";
    format = "binary";
    download_detour = "upstream";
  };

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

  # -> tag, server, server_port, password
  # -> tls.server_name tls.certificate_path tls.ech.config_path
  mkHysteria2 = mapMergeEntries {
    type = "hysteria2";
    up_mbps = 30;
    down_mbps = 100;
    tls = {
      enabled = true;
      alpn = [ "h3" ];
      ech = {
        enabled = true;
      };
    };
  };

  # _host_id, _prefixes, public_key, pre_shared_key
  mkWireGuardPeers =
    l:
    let
      splits = splitWithPrefixEntries "_" l;
      listOfIPs = map (attrs: {
        allowed_ips = map (
          prefix:
          if lib.hasInfix ":" prefix then
            "${prefix}${builtins.toString attrs._host_id}/128" # IPv6
          else
            "${prefix}${builtins.toString attrs._host_id}/32" # IPv4
        ) attrs._prefixes;
      }) splits._true;
    in
    combineEntries splits._false listOfIPs;

  # _name, url
  mkProviders =
    l:
    let
      splits = splitWithPrefixEntries "_" l;
      names = map (attrs: {
        tag = attrs._name;
        cache_file = "/var/lib/loadbalance/providers/${attrs._name}";
      }) splits._true;
      value = combineEntries splits._false names;
    in
    mapMergeEntries {
      type = "http";
      download_detour = "direct";
    } value;
}
