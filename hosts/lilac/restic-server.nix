{
  ctx,
  lib,
  pkgs,
  ...
}:
let
  srv = ctx.services.restic-server;
  rcloneConf = ctx.vars.rclone-gdrive.conf;
  htpasswdFile = pkgs.writeText "rclone-restic.htpasswd" (
    lib.concatStringsSep "\n" srv.htpasswd-entries + "\n"
  );
in
{
  systemd.services.rclone-restic = {
    description = "Restic REST server backed by rclone";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "rclone-restic";
      LoadCredential = "rclone.conf:${rcloneConf.path}";
      UMask = "0077";
      MemoryMax = "256M";
      NoNewPrivileges = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
      ];
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "@chown"
      ];
      SystemCallErrorNumber = "EPERM";
      Restart = "on-failure";
      RestartSec = "10s";
    };
    script = ''
      set -euo pipefail
      conf="$STATE_DIRECTORY/rclone.conf"
      # Seed writable copy so rclone can persist refreshed OAuth tokens.
      if [ ! -s "$conf" ]; then
        install -m 0600 "$CREDENTIALS_DIRECTORY/rclone.conf" "$conf"
      fi
      exec ${lib.getExe pkgs.rclone} serve restic \
        --config "$conf" \
        --addr "127.0.0.1:${toString srv.port}" \
        --htpasswd ${htpasswdFile} \
        --private-repos \
        --tpslimit 4 \
        --tpslimit-burst 8 \
        ${lib.escapeShellArg srv.remote}
    '';
  };

  services.caddy = {
    enable = true;
    virtualHosts.${srv.domain} = {
      listenAddresses = ctx.tailscale.ips;
      useACMEHost = ctx.metadata.fdqn;
      extraConfig = ''
        request_body {
          max_size 64MB
        }
        reverse_proxy 127.0.0.1:${toString srv.port} {
          flush_interval -1
        }
      '';
    };
  };
}
