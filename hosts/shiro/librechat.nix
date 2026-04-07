{
  pkgs,
  ctx,
  registry,
  ...
}:
let
  librechat = ctx.services.librechat;
  fetchJwt = pkgs.writeShellScript "fetch-gcp-jwt" ''
    set -euo pipefail
    BAO="${registry.openbao.url}"
    ROLE_ID=$(cat ${librechat.wif.role-id.path})
    SECRET_ID=$(cat ${librechat.wif.secret-id.path})

    TOKEN=$(${pkgs.curl}/bin/curl -sf "$BAO/v1/auth/approle/login" \
      -H "Content-Type: application/json" \
      -d "{\"role_id\":\"$ROLE_ID\",\"secret_id\":\"$SECRET_ID\"}" \
      | ${pkgs.jq}/bin/jq -r '.auth.client_token')

    ${pkgs.curl}/bin/curl -sf "$BAO/v1/identity/oidc/token/vertex-oidc-role" \
      -H "X-Vault-Token: $TOKEN" \
      | ${pkgs.jq}/bin/jq -r '.data.token' > /run/librechat/bao_jwt
  '';
in
{
  imports = [
    ./librechat-container.nix
  ];

  # dedicated user for the JWT fetcher and container
  users.users.librechat = {
    isSystemUser = true;
    group = "librechat";
  };
  users.groups.librechat = { };

  systemd.tmpfiles.rules = [
    "d /run/librechat 0750 librechat librechat -"
  ];

  sops.secrets."${librechat.wif.role-id.name}".owner = "librechat";
  sops.secrets."${librechat.wif.secret-id.name}".owner = "librechat";
  systemd.services.librechat-wif = {
    description = "Fetch GCP WIF JWT from OpenBao";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = fetchJwt;
      User = "librechat";
      Group = "librechat";
    };
  };

  systemd.timers.librechat-wif = {
    description = "Refresh GCP WIF JWT every 45 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "30s"; # run shortly after boot
      OnUnitActiveSec = "45min"; # refresh before 1h TTL expires
    };
  };

  core.acme.certs."${librechat.domain}" = {
    reloadServices = [ "caddy.service" ];
  };
  services.caddy = {
    enable = true;
    virtualHosts."${librechat.domain}" = {
      listenAddresses = ctx.tailscale.ips;
      extraConfig = ''
        tls /var/lib/acme/${librechat.domain}/cert.pem /var/lib/acme/${librechat.domain}/key.pem
        reverse_proxy 127.0.0.1:3080 {
          flush_interval -1

          transport http {
            read_timeout 300s
            write_timeout 300s
            dial_timeout 30s
            keepalive 300s
          }

          header_up Connection "keep-alive"
          header_up -Accept-Encoding
        }
      '';
    };
  };
}
