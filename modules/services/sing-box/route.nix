{
  config,
  lib,
  ...
}:
let
  cfg = config.infra.sing-box;
in
{
  config = lib.mkIf cfg.enable {
    infra.sing-box.settings.route = {
      rules = lib.mkBefore [
        {
          inbound = cfg.inbounds;
          action = "sniff";
          timeout = "1s";
        }
        {
          protocol = [ "bittorrent" ];
          action = "reject";
        }
        {
          ip_is_private = true;
          action = "reject";
        }
        {
          port = [
            # unencrypted mail
            25
            # smb/netbios
            135
            137
            138
            139
            445
          ];
          action = "reject";
        }
        {
          # These services are unreachable through WARP on some routes.
          domain_suffix = [
            "archive.org"
            "lit.link"
          ];
          outbound = "direct";
        }
      ];
      final = if (cfg.warp-svc.enable || cfg.usque.enable) then "warp" else "direct";
    };
  };
}
