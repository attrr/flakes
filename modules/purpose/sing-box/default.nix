{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.core.server.sing-box;
  jsonFormat = pkgs.formats.json { };
in
{
  imports = [
    ./shadowsocks.nix
    ./hysteria2.nix
    ./warp.nix
    ./lowend.nix
  ];

  options.core.server.sing-box = {
    enable = lib.mkEnableOption "enable sing-box server setup";
    uid = lib.mkOption {
      type = lib.types.int;
      default = 992;
    };
    gid = lib.mkOption {
      type = lib.types.int;
      default = 992;
    };
    settings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    # internal only
    secrets = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.path lib.types.str);
      default = [ ];
      internal = true;
    };
    tcpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      internal = true;
    };
    udpPorts = lib.mkOption {
      type = lib.types.listOf lib.types.port;
      default = [ ];
      internal = true;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.shadowsocks.enable || cfg.hysteria2.enable;
        message = "Error: one of shadowsocks or hysteria2 inbound has to be enabled";
      }
    ];

    # default settings
    core.server.sing-box.settings = {
      dns = {
        servers = [
          {
            type = "https";
            server = "1.0.0.1";
            tag = "local";
            detour = "direct";
          }
        ];
        strategy = "prefer_ipv6";
        final = "local";
      };
      outbounds = [
        {
          type = "direct";
          tag = "direct";
          domain_resolver = "local";
        }
        {
          type = "shadowsocks";
          tag = "warp";
          method = "none";
          server = "127.0.0.1";
          server_port = 1080;
        }
      ];
      route.final = if cfg.warp.enable then "warp" else "direct";
      log.level = "error";
    };

    # to match permission inside/outside of container
    users = {
      users.sing-box = {
        isSystemUser = true;
        uid = cfg.uid;
        group = "sing-box";
      };
      groups.sing-box = {
        gid = cfg.gid;
      };
    };

    containers.sing-box = {
      autoStart = true;
      ephemeral = true;
      privateNetwork = false;

      bindMounts =
        lib.genAttrs
          (builtins.filter (path: path != "" && !(lib.hasPrefix builtins.storeDir path)) cfg.secrets)
          (path: {
            hostPath = path;
            isReadOnly = true;
          });
      config =
        { ... }:
        {
          users.users.sing-box.uid = cfg.uid;
          users.groups.sing-box.gid = cfg.gid;
          services.sing-box = {
            enable = true;
            settings = cfg.settings;
          };
          system.stateVersion = "25.11";
        };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = cfg.tcpPorts;
      allowedUDPPorts = cfg.udpPorts;
    };
  };
}
