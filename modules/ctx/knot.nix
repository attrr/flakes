{
  ctx,
  global,
  lib,
  ...
}:
let
  knot = ctx.services.knot or { };
  enabled = knot.enable or false;
  isMaster = enabled && (knot ? slaves);
  isSlave = enabled && !isMaster;
in
{
  infra.knot = lib.mkIf enabled {
    domain = lib.mkDefault global.domain.main;
    listenAddresses = lib.mkDefault ctx.tailscale.ips;
    tsigKeyFile = lib.mkDefault knot.tsig-key.path;

    master = lib.mkIf isMaster {
      enable = lib.mkDefault true;
      slaves = lib.mkDefault knot.slaves;
    };

    slave = lib.mkIf isSlave {
      enable = lib.mkDefault true;
      masterIPs = lib.mkDefault knot.master-ips;
    };
  };

  sops.secrets = lib.mkIf enabled {
    ${knot.tsig-key.name}.owner = "knot";
  };

  networking.firewall.interfaces.tailscale0 = lib.mkIf enabled {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };
}
