# Static network topology (gated by `infra.network.topology == "static"`).
{
  nixos =
    {
      config,
      helpers,
      lib,
      ...
    }:
    let
      cfg = config.infra.network;
    in
    {
      config = lib.mkIf (cfg.topology == "static") (
        lib.mkMerge [
          {
            networking = {
              useNetworkd = lib.mkDefault true;
              nameservers = lib.mkDefault (
                [
                  "1.1.1.1"
                  "8.8.8.8"
                ]
                ++ lib.optional (cfg.ipv6.addresses != [ ]) "2606:4700:4700::1111"
              );
            };
          }

          (lib.mkIf config.networking.useNetworkd {
            systemd.network.networks."10-default" = {
              matchConfig.Name = if cfg.interface != null then cfg.interface else "e*";
              address = cfg.ipv4.addresses ++ cfg.ipv6.addresses;
              gateway = lib.filter (x: x != null) [
                cfg.ipv4.gateway
                cfg.ipv6.gateway
              ];
            };
          })

          (lib.mkIf (!config.networking.useNetworkd) (
            let
              iface = if cfg.interface != null then cfg.interface else "eth0";
              toGw = address: {
                inherit address;
                interface = iface;
              };
            in
            {
              networking = {
                useDHCP = false;
                interfaces.${iface} = {
                  ipv4.addresses = map helpers.network.parseCidr cfg.ipv4.addresses;
                  ipv6.addresses = map helpers.network.parseCidr cfg.ipv6.addresses;
                };
                defaultGateway = lib.mapNullable toGw cfg.ipv4.gateway;
                defaultGateway6 = lib.mapNullable toGw cfg.ipv6.gateway;
              };
            }
          ))
        ]
      );
    };

  finix =
    { config, lib, ... }:
    let
      cap = config.infra.container.capabilities;
      infraNet = config.infra.network;
      iface = if infraNet.interface != null then infraNet.interface else "eth0";
      addrs = infraNet.ipv4.addresses ++ infraNet.ipv6.addresses;
      gws = lib.filter (g: g != null) [
        infraNet.ipv4.gateway
        infraNet.ipv6.gateway
      ];
    in
    {
      config = lib.mkIf (cap.net_admin && infraNet.topology == "static") {
        networking.nameservers = lib.mkDefault (
          [
            "1.1.1.1"
            "8.8.8.8"
          ]
          ++ lib.optional (
            infraNet.ipv6.addresses != [ ] || config.infra.tunnelbroker.enable
          ) "2606:4700:4700::1111"
        );

        environment.etc."resolv.conf".text = lib.concatMapStrings (
          ns: "nameserver ${ns}\n"
        ) config.networking.nameservers;

        programs.ifupdown-ng = {
          auto = lib.optional (addrs != [ ]) iface;
          iface.${iface} = lib.mkIf (addrs != [ ]) {
            address = addrs;
            gateway = lib.mkIf (gws != [ ]) gws;
          };
        };
      };
    };
}
