# Multi-class `infra.sing-box` feature (pure module + exitnode ctx wiring).
{
  includes = [ ../usque ];

  module = {
    common = ./common.nix;

    nixos =
      { config, lib, ... }:
      let
        cfg = config.infra.sing-box;
      in
      {
        imports = [
          ./warp-svc.nix
          ./lowend.nix
        ];

        options.infra.sing-box = {
          openFirewall = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          isolated = lib.mkOption {
            type = lib.types.bool;
            default = !config.boot.isContainer;
            description = "Run sing-box inside an ephemeral systemd-nspawn container instead of directly on the host.";
          };
        };

        config = lib.mkIf cfg.enable {
          # to match permission inside/outside of container
          users = lib.mkIf cfg.isolated {
            users.sing-box = {
              isSystemUser = true;
              uid = cfg.uid;
              group = "sing-box";
            };
            groups.sing-box = {
              gid = cfg.gid;
            };
          };

          containers.sing-box = lib.mkIf cfg.isolated {
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
                services.journald.extraConfig = ''
                  Storage=volatile
                  RuntimeMaxUse=32M
                '';
                system.stateVersion = config.system.stateVersion;
              };
          };

          services.sing-box = lib.mkIf (!cfg.isolated) {
            enable = true;
            settings = cfg.settings;
          };

          networking.firewall = lib.mkIf cfg.openFirewall {
            allowedTCPPorts = cfg.tcpPorts;
            allowedUDPPorts = cfg.udpPorts;
          };
        };
      };

    finix =
      { config, lib, ... }:
      let
        cfg = config.infra.sing-box;
      in
      {
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
      };
  };

  ctx = {
    common =
      { ctx, lib, ... }:
      let
        exitnode = ctx.services.exitnode;
        shadowsocks = exitnode.shadowsocks;
        hysteria2 = exitnode.hysteria2;
        vless = exitnode.vless;
      in
      {
        infra.sing-box = lib.mkIf exitnode.enable {
          enable = lib.mkDefault true;
          usque = {
            enable = lib.mkDefault (exitnode.outbound.type == "usque");
            ipv6 = lib.mkDefault (builtins.elem "ipv6-only" ctx.metadata.tags);
            http2 = lib.mkDefault exitnode.outbound.usque.http2;
          };

          shadowsocks = {
            enable = lib.mkDefault shadowsocks.enable;
            listen = lib.mkIf shadowsocks.enable shadowsocks.listen-address;
            port = lib.mkIf shadowsocks.enable shadowsocks.port;
            passwordPath = lib.mkIf shadowsocks.enable shadowsocks.password.path;
          };

          hysteria2 = lib.mkIf hysteria2.enable {
            enable = true;
            listen = hysteria2.listen-address;
            port = hysteria2.port;
            upMbps = hysteria2.up-mbps;
            downMbps = hysteria2.down-mbps;
            passwordPath = hysteria2.password.path;
            tlsCertificatePath = hysteria2.tls.cert;
            tlsKeyPath = hysteria2.tls.key.path;
            echKeyPath = hysteria2.tls.ech-key.path;
          };

          vless = lib.mkIf vless.enable {
            enable = true;
            listen = vless.listen-address;
            port = vless.port;
            uuidPath = vless.uuid.path;
            privateKey = vless.private-key.path;
            shortIdPath = vless.short-id.path;
            serverName = vless.server-name;
          };
        };
      };

    finix =
      {
        config,
        ctx,
        lib,
        ...
      }:
      let
        memMb = ctx.metadata.specs.memory;
        lowMem = memMb != null && memMb <= 96;
      in
      {
        # Keep Go's memory target within tight container limits (`default` is 64MiB/48MiB).
        finit.services = lib.mkMerge [
          (lib.mkIf (config.services.sing-box.enable && lowMem) {
            sing-box.environment = {
              GOMEMLIMIT = lib.mkOverride 900 "${toString (lib.max 16 (memMb * 7 / 16))}MiB";
              GOGC = lib.mkOverride 900 25;
            };
          })
          (lib.mkIf (config.services.usque.enable && lowMem) {
            usque.environment = {
              GOMEMLIMIT = lib.mkOverride 900 "${toString (lib.max 12 (memMb / 4))}MiB";
              GOGC = lib.mkOverride 900 25;
            };
          })
        ];
      };
  };
}
