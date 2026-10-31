# ctx -> rescue: global rescue-only keys, the host's port, and its static
# addresses so hosts without DHCP (ipv6-only, static v4) are reachable right after boot.
{
  lib,
  ctx,
  global,
  ...
}:
let
  net = ctx.network;
  has = stack: net.${stack}.cidr != [ ];
in
{
  networking.hostName = "${ctx.metadata.hostname}-rescue";

  rescue.ssh = {
    port = lib.head ctx.ssh.ports;
    authorizedKeys =
      if global.rescue-keys != [ ] then
        global.rescue-keys
      else
        throw "ctx: global.rescue-keys is empty, add a key in ctx/common/default.nix";
  };

  boot.initrd.systemd.network.networks."10-ctx" = lib.mkIf (has "ipv4" || has "ipv6") {
    matchConfig =
      if net.mac-address != null then { MACAddress = net.mac-address; } else { Name = "en* eth*"; };
    networkConfig = {
      DHCP = if has "ipv4" then "no" else "ipv4";
      IPv6AcceptRA = true;
    };
    address = net.ipv4.cidr ++ net.ipv6.cidr;
    routes = map (Gateway: {
      inherit Gateway;
      GatewayOnLink = true;
    }) (lib.filter (g: g != null) [ net.ipv4.gateway net.ipv6.gateway ]);
  };
}
