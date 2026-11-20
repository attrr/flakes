{
  config,
  lib,
  ...
}:
let
  cap = config.infra.container.capabilities;
  infraNet = config.infra.network;

  stackType = lib.types.submodule {
    options = {
      addresses = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
      };
      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };

  iface = if infraNet.interface != null then infraNet.interface else "eth0";
  addrs = infraNet.ipv4.addresses ++ infraNet.ipv6.addresses;
  gws = lib.filter (g: g != null) [
    infraNet.ipv4.gateway
    infraNet.ipv6.gateway
  ];
in
{
  options.infra.network = {
    topology = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum [ "static" ]);
      default = null;
    };
    interface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    ipv4 = lib.mkOption {
      type = stackType;
      default = { };
    };
    ipv6 = lib.mkOption {
      type = stackType;
      default = { };
    };
  };

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
}
