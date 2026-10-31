# ctx -> rescue: same keys/port as the host, and its static addresses so
# hosts without DHCP (ipv6-only, static v4) are reachable right after boot.
{ lib, ctx, ... }:
let
  net = ctx.network;
  has = stack: net.${stack}.cidr != [ ];
in
{
  networking.hostName = "${ctx.metadata.hostname}-rescue";

  rescue.ssh = {
    port = lib.head ctx.ssh.ports;
    authorizedKeys = ctx.ssh.auth-keys;
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
