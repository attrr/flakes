{ config, lib, pkgs, ... }:
let
  cfg = config.infra.sing-box.usque;
  socksAddr = "127.0.0.1";
  socksPort = cfg.port;
in
{
  options.infra.sing-box.usque = {
    enable = lib.mkEnableOption "usque MASQUE-based WARP backend for sing-box";

    port = lib.mkOption {
      type = lib.types.port;
      default = 1080;
      description = "Local SOCKS5 port usque listens on (consumed by sing-box as outbound).";
    };
  };

  config = lib.mkIf (config.infra.sing-box.enable && cfg.enable) {
    assertions = [
      {
        assertion = !(config.infra.sing-box.warp.enable && cfg.enable);
        message = "infra.sing-box.usque and infra.sing-box.warp cannot both be enabled.";
      }
    ];

    # Wire usque's SOCKS5 as the sing-box "warp" outbound, reusing the same
    # outbound tag so default.nix route rules need no changes.
    infra.sing-box.settings.outbounds = lib.mkAfter [
      {
        type = "socks";
        tag = "warp";
        server = socksAddr;
        server_port = socksPort;
        version = "5";
      }
    ];

    users.users.usque = {
      isSystemUser = true;
      group = "usque";
      home = "/var/lib/usque";
      description = "usque WARP MASQUE daemon";
    };
    users.groups.usque = { };

    systemd.services.usque = {
      description = "usque — Cloudflare WARP MASQUE client";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        User = "usque";
        Group = "usque";
        StateDirectory = "usque";
        WorkingDirectory = "/var/lib/usque";

        # Register once on first boot; subsequent starts skip this.
        ExecStartPre = pkgs.writeShellScript "usque-register" ''
          if [ ! -f /var/lib/usque/config.json ]; then
            echo "usque: no config.json found, registering new WARP account..."
            ${lib.getExe pkgs.usque} register --accept-tos
          fi
        '';

        ExecStart = "${lib.getExe pkgs.usque} socks -b ${socksAddr} -p ${toString socksPort}";

        Restart = "on-failure";
        RestartSec = "5s";

        # Hardening
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/usque" ];
      };
    };
  };
}
