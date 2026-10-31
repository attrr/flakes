# ctx -> rescue: global rescue-only keys, the host's port, and its static
# addresses so hosts without DHCP (ipv6-only, static v4) are reachable right after boot.
# Every value is mkDefault, and the network sits at 50 (before the 99 DHCP fallback),
# so bootstrap/hosts/<host>.nix can override fields or add an earlier 10-* network.
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
  networking.hostName = lib.mkDefault "${ctx.metadata.hostname}-rescue";

  rescue.ssh = lib.mkDefault {
    port = lib.head ctx.ssh.ports;
    authorizedKeys =
      if global.rescue-keys != [ ] then
        global.rescue-keys
      else
        throw "ctx: global.rescue-keys is empty, add a key in ctx/common/default.nix";
  };

  # mkDefault per field: on the whole network, any host override would drop all of it
  boot.initrd.systemd.network.networks."50-ctx" = lib.mkIf (has "ipv4" || has "ipv6") {
    # networkd always defines matchConfig = { } at normal priority, so per key too
    matchConfig = lib.mapAttrs (_: lib.mkDefault) (
      if net.mac-address != null then { MACAddress = net.mac-address; } else { Name = "en* eth*"; }
    );
    networkConfig = lib.mapAttrs (_: lib.mkDefault) {
      DHCP = if has "ipv4" then "no" else "ipv4";
      IPv6AcceptRA = true;
    };
    address = lib.mkDefault (net.ipv4.cidr ++ net.ipv6.cidr);
    routes = lib.mkDefault (
      map (Gateway: {
        inherit Gateway;
        GatewayOnLink = true;
      }) (lib.filter (g: g != null) [ net.ipv4.gateway net.ipv6.gateway ])
    );
  };
}
