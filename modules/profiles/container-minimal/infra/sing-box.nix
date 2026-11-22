{
  config,
  lib,
  self,
  ...
}:
let
  cfg = config.infra.sing-box;
in
{
  imports = [
    "${self}/modules/services/sing-box/common.nix"
  ];

  options.infra.sing-box.warp-svc.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    internal = true;
  };

  config = lib.mkIf cfg.enable {
    users.users.sing-box.uid = cfg.uid;
    users.groups.sing-box.gid = cfg.gid;

    services.sing-box = {
      enable = true;
      inherit (cfg) settings;
    };

    providers.firewall = lib.mkIf (config.providers.firewall.backend != "none") {
      allowedTCPPorts = cfg.tcpPorts;
      allowedUDPPorts = cfg.udpPorts;
    };
  };
}
