# Authoritative Knot DNS over tailnet; shared base for master and slave roles.
{
  config,
  lib,
  ...
}:
let
  cfg = config.infra.knot;
  enabled = cfg.master.enable || cfg.slave.enable;
in
{
  imports = [
    ./master.nix
    ./slave.nix
  ];

  options.infra.knot = {
    domain = lib.mkOption {
      type = lib.types.str;
      description = "Primary zone domain served by Knot DNS.";
    };

    listenAddresses = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "IP addresses (without port) for Knot DNS to listen on.";
    };

    tsigKeyFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to the TSIG key file.";
    };

    openFirewall = lib.mkEnableOption "opening firewall ports 53/tcp and 53/udp for Knot DNS";
  };

  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = !(cfg.master.enable && cfg.slave.enable);
        message = "infra.knot.master and infra.knot.slave are mutually exclusive.";
      }
    ];

    services.knot = {
      enable = true;
      keyFiles = [ cfg.tsigKeyFile ];

      settings = {
        server = {
          listen = map (s: "${s}@53") cfg.listenAddresses;
          user = "knot";
        };

        mod-rrl = [
          {
            id = "default";
            rate-limit = 100; # 100 resp/s
            slip = 2;
          }
        ];

        mod-cookies = [
          {
            id = "default";
            secret-lifetime = "30h";
            badcookie-slip = 3;
          }
        ];

        template.default = {
          global-module = [
            "mod-rrl/default"
            "mod-cookies/default"
          ];
          storage = "/var/lib/knot/zones";
        };
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ 53 ];
      allowedUDPPorts = [ 53 ];
    };
  };
}
