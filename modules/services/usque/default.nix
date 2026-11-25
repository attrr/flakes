{
  common =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.usque;
    in
    {
      options.services.usque = {
        enable = lib.mkEnableOption "usque Cloudflare WARP MASQUE client";

        package = lib.mkPackageOption pkgs "usque" { };

        socksAddr = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1";
          description = "Local address usque SOCKS5 listens on.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 1080;
          description = "Local port usque SOCKS5 listens on.";
        };

        ipv6 = lib.mkEnableOption "use IPv6 for MASQUE connection";

        http2 = lib.mkEnableOption "use HTTP/2 over TCP+TLS instead of HTTP/3 over QUIC";
      };

      config = lib.mkIf cfg.enable {
        users.users.usque = {
          group = "usque";
          home = "/var/lib/usque";
          description = "usque WARP MASQUE daemon";
        };
        users.groups.usque = { };
      };
    };

  nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.usque;
    in
    {
      config = lib.mkIf cfg.enable {
        users.users.usque.isSystemUser = true;

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
                ${lib.getExe cfg.package} register --accept-tos
              fi
            '';

            ExecStart =
              "${lib.getExe cfg.package} socks -b ${cfg.socksAddr} -p ${toString cfg.port} --always-reconnect"
              + lib.optionalString cfg.ipv6 " -6"
              + lib.optionalString cfg.http2 " --http2";

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
    };

  finix =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.usque;
      coreutils = config.programs.coreutils.package;
    in
    {
      config = lib.mkMerge [
        {
          services.usque.package = lib.mkDefault pkgs.usque-strip;
        }
        (lib.mkIf cfg.enable {
          environment.systemPackages = [ cfg.package ];

          finit.services.usque = {
            description = "usque Cloudflare WARP MASQUE client";
            conditions = lib.optionals config.programs.ifupdown-ng.enable [ "task/ifupdown-ng/success" ];
            user = "usque";
            group = "usque";
            state-dir = "usque";
            state-dir-mode = "0700";
            reload-signal = "none";
            environment = {
              GOMEMLIMIT = lib.mkDefault "48MiB";
              GOGC = lib.mkDefault 50;
            };
            exec-start-pre = pkgs.writeScript "usque-register" ''
              #!${coreutils}/bin/sh
              if [ ! -f /var/lib/usque/config.json ]; then
                cd /var/lib/usque
                ${lib.getExe cfg.package} register --accept-tos
              fi
            '';
            script = ''
              cd /var/lib/usque
              exec ${
                lib.concatStringsSep " " (
                  [
                    (lib.getExe cfg.package)
                    "socks"
                    "-b ${cfg.socksAddr}"
                    "-p ${toString cfg.port}"
                    "--always-reconnect"
                  ]
                  ++ lib.optional cfg.ipv6 "-6"
                  ++ lib.optional cfg.http2 "--http2"
                )
              }
            '';
          };
        })
      ];
    };
}
