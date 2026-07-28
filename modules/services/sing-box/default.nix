{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.sing-box;
  jsonFormat = pkgs.formats.json { };
in
{
  imports = [
    ./shadowsocks.nix
    ./hysteria2.nix
    ./vless.nix
    ./warp-svc.nix
    ./usque.nix
    ./lowend.nix
    ./route.nix
  ];

  options.infra.sing-box = {
    enable = lib.mkEnableOption "enable sing-box server setup";
    uid = lib.mkOption {
      type = lib.types.int;
      default = 992;
      description = "UID for the sing-box system user (must match inside the container).";
    };
    gid = lib.mkOption {
      type = lib.types.int;
      default = 992;
      description = "GID for the sing-box system group (must match inside the container).";
    };
    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = jsonFormat.type;
      };
      default = { };
    };
    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };

    # internal only
    inbounds = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      internal = true;
    };
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
        assertion = cfg.shadowsocks.enable || cfg.hysteria2.enable || cfg.vless.enable;
        message = "Error: at least one inbound (shadowsocks, hysteria2, or vless) must be enabled";
      }
    ];

    boot.kernel.sysctl = {
      "net.ipv4.ip_local_port_range" = lib.mkDefault "1024 65535";
      # enable tcp socket reuse
      "net.ipv4.tcp_timestamps" = lib.mkDefault 1;
      "net.ipv4.tcp_tw_reuse" = lib.mkDefault 1;
      # increase tcp conn limit
      "net.core.somaxconn" = lib.mkDefault 4096;
      "net.ipv4.tcp_max_syn_backlog" = lib.mkDefault 4096;
      # quicken tcp conn recycle
      "net.ipv4.tcp_fin_timeout" = lib.mkDefault 30;
      "net.ipv4.tcp_keepalive_time" = lib.mkDefault 1800;
      # conserve nf_conntrack
      "net.netfilter.nf_conntrack_max" = lib.mkDefault 1048576;
      "net.netfilter.nf_conntrack_tcp_timeout_established" = lib.mkDefault 86400;
      "net.netfilter.nf_conntrack_udp_timeout_stream" = lib.mkDefault 60;
      "net.netfilter.nf_conntrack_tcp_timeout_time_wait" = lib.mkDefault 60;
      "net.netfilter.nf_conntrack_tcp_timeout_fin_wait" = lib.mkDefault 60;
      # for quic-go
      "net.core.rmem_max" = lib.mkDefault 16777216;
      "net.core.wmem_max" = lib.mkDefault 16777216;
    };

    # default settings
    infra.sing-box.settings = {
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
      ];
      log.level = lib.mkDefault "error";
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
          system.stateVersion = config.system.stateVersion;
        };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = cfg.tcpPorts;
      allowedUDPPorts = cfg.udpPorts;
    };
  };
}
