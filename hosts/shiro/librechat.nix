{
  config,
  lib,
  pkgs,
  ctx,
  self,
  registry,
  ...
}:
let
  librechat = ctx.services.librechat;
  # the host's end of the container's veth, and the container's
  hostAddress = "10.233.1.1";
  localAddress = "10.233.1.2";
  containerRoot = "/var/lib/nixos-containers/librechat";
  inherit (librechat) secrets;
  templates = config.sops.templates;
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
  # dedicated user for the JWT fetcher, mirrored in the container
  users.users.librechat = {
    isSystemUser = true;
    group = "librechat";
    uid = 991;
  };
  users.groups.librechat.gid = 988;

  systemd.tmpfiles.rules = [
    "d /run/librechat 0750 librechat librechat -"
    "C+ /run/librechat/account.json 0640 librechat librechat - ${librechat.wif.vertex-service-account}"
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

  # nixpkgs' litellm only takes an env file
  sops.templates."librechat-litellm.env".content =
    "LITELLM_MASTER_KEY=${secrets.litellm-master-key.ph}\n";

  containers.librechat = {
    autoStart = true;
    privateNetwork = true;
    inherit hostAddress localAddress;
    # secrets at the same paths as on the host; read when the container
    # starts, restart it after changing one
    bindMounts =
      lib.genAttrs
        (
          [
            "/run/librechat"
            librechat.env.path
            templates."librechat-litellm.env".path
          ]
          ++ map (s: s.path) (lib.attrValues secrets)
        )
        (_: {
          isReadOnly = true;
        });
    specialArgs = { inherit ctx; };
    # what depends on the host's config
    config = {
      # containers only get nixos' own modules
      imports = [
        "${self}/modules/services/librechat-rag-api"
        ./librechat-container.nix
      ];
      nixpkgs.pkgs = pkgs;
      networking.nameservers = [ hostAddress ];
      # owns the bind mounted /run/librechat
      users.users.librechat.uid = config.users.users.librechat.uid;
      users.groups.librechat.gid = config.users.groups.librechat.gid;
      services.litellm.environmentFile = templates."librechat-litellm.env".path;
    };
  };
  allowUnfree = {
    enable = true;
    packages = [ pkgs.mongodb-ce ];
  };

  # egress, and dns through the host's resolved
  networking.nat = {
    enable = true;
    internalInterfaces = [ "ve-librechat" ];
    # masquerade only out the uplink, so tailnet peers can't answer the container
    # (tailscaled's own 100.100.100.100 still does)
    externalInterface = ctx.network.interface;
  };
  assertions = [
    {
      assertion = ctx.network.interface != null;
      message = "librechat: ctx network.interface unset, the container would be NATed onto the tailnet";
    }
  ];
  services.resolved.settings.Resolve.DNSStubListenerExtra = [ hostAddress ];
  networking.firewall.interfaces.ve-librechat = {
    allowedTCPPorts = [ 53 ];
    allowedUDPPorts = [ 53 ];
  };

  infra.acme.certs."${librechat.domain}" = { };
  services.caddy = {
    enable = true;
    virtualHosts."${librechat.domain}" = {
      listenAddresses = ctx.tailscale.ips;
      useACMEHost = librechat.domain;
      extraConfig = ''
        reverse_proxy ${localAddress}:${toString librechat.port} {
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

  infra.restic.backups.librechat =
    let
      target = "/var/backup/librechat";
    in
    {
      paths = [
        target
        "${containerRoot}/var/lib/librechat/uploads"
        "${containerRoot}/var/lib/librechat/images"
      ];

      backupPrepareCommand = ''
        rm -rf ${target}
        mkdir -p ${target}

        run() { ${pkgs.nixos-container}/bin/nixos-container run librechat -- "$@"; }
        run mongodump --quiet --archive > ${target}/mongo.archive
        run runuser -u postgres -- pg_dump librechat-rag-api > ${target}/pgvector.dump
      '';
      backupCleanupCommand = ''
        rm -rf ${target}
      '';
    };

  networking.firewall.interfaces.tailscale0 = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };
}
