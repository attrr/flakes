{
  module.nixos =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.infra.librechat;
      containerRoot = "/var/lib/nixos-containers/librechat";
      fetchJwt = pkgs.writeShellScript "fetch-gcp-jwt" ''
        set -euo pipefail
        umask 0077
        BAO=${lib.escapeShellArg cfg.wif.openbaoUrl}

        TOKEN=$(
          ${pkgs.jq}/bin/jq -n \
            --rawfile role_id ${lib.escapeShellArg cfg.wif.roleIdFile} \
            --rawfile secret_id ${lib.escapeShellArg cfg.wif.secretIdFile} \
            '{role_id: ($role_id | rtrimstr("\n")), secret_id: ($secret_id | rtrimstr("\n"))}' \
          | ${pkgs.curl}/bin/curl -sf "$BAO/v1/auth/approle/login" \
              -H "Content-Type: application/json" \
              --data-binary @- \
          | ${pkgs.jq}/bin/jq -er '.auth.client_token'
        )

        JWT=$(
          ${pkgs.curl}/bin/curl -sf "$BAO/v1/identity/oidc/token/vertex-oidc-role" \
            -H @<(printf 'X-Vault-Token: %s' "$TOKEN") \
          | ${pkgs.jq}/bin/jq -er '.data.token'
        )

        printf '%s\n' "$JWT" > /run/librechat/bao_jwt.tmp
        chmod 0640 /run/librechat/bao_jwt.tmp
        mv -f /run/librechat/bao_jwt.tmp /run/librechat/bao_jwt
      '';
    in
    {
      options.infra.librechat = {
        enable = lib.mkEnableOption "LibreChat in a NixOS container with LiteLLM and RAG API";

        domain = lib.mkOption {
          type = lib.types.str;
          description = "Domain for Caddy virtualHost and ACME certificate";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 3080;
          description = "LibreChat HTTP port inside the container";
        };

        configFile = lib.mkOption {
          type = lib.types.path;
          description = "Path to librechat.yaml";
        };

        envFile = lib.mkOption {
          type = lib.types.str;
          description = "Path to environment file of third-party API keys";
        };

        secrets = {
          credsKey = lib.mkOption {
            type = lib.types.str;
            description = "Path to CREDS_KEY secret file";
          };
          credsIv = lib.mkOption {
            type = lib.types.str;
            description = "Path to CREDS_IV secret file";
          };
          jwtSecret = lib.mkOption {
            type = lib.types.str;
            description = "Path to JWT_SECRET secret file";
          };
          jwtRefreshSecret = lib.mkOption {
            type = lib.types.str;
            description = "Path to JWT_REFRESH_SECRET secret file";
          };
          meiliMasterKey = lib.mkOption {
            type = lib.types.str;
            description = "Path to MEILI_MASTER_KEY secret file";
          };
          litellmMasterKey = lib.mkOption {
            type = lib.types.str;
            description = "Path to LITELLM_MASTER_KEY secret file";
          };
          litellmMasterKeyEnvFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to env file defining LITELLM_MASTER_KEY";
          };
        };

        wif = {
          openbaoUrl = lib.mkOption {
            type = lib.types.str;
            description = "OpenBao base URL used to fetch GCP WIF JWT";
          };
          roleIdFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to OpenBao AppRole role_id file";
          };
          secretIdFile = lib.mkOption {
            type = lib.types.str;
            description = "Path to OpenBao AppRole secret_id file";
          };
          vertexServiceAccount = lib.mkOption {
            type = lib.types.path;
            description = "Path to Vertex AI WIF service account JSON";
          };
        };

        network = {
          hostAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.233.1.1";
            description = "Host-side veth address for the librechat container";
          };
          localAddress = lib.mkOption {
            type = lib.types.str;
            default = "10.233.1.2";
            description = "Container-side veth address for the librechat container";
          };
          externalInterface = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            description = "Uplink interface for container egress NAT";
          };
          listenAddresses = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "Addresses Caddy virtualHost listens on";
          };
        };

        backup.enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable restic backup for LibreChat when infra.restic is enabled";
        };
      };

      config = lib.mkIf cfg.enable {
        infra.secrets = [
          {
            path = cfg.wif.roleIdFile;
            owner = "librechat";
          }
          {
            path = cfg.wif.secretIdFile;
            owner = "librechat";
          }
        ];

        # dedicated user for the JWT fetcher, mirrored in the container
        users.users.librechat = {
          isSystemUser = true;
          group = "librechat";
          uid = 991;
        };
        users.groups.librechat.gid = 988;

        systemd.tmpfiles.rules = [
          "d /run/librechat 0750 librechat librechat -"
          "C+ /run/librechat/account.json 0640 librechat librechat - ${cfg.wif.vertexServiceAccount}"
        ];

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

        containers.librechat = {
          autoStart = true;
          privateNetwork = true;
          inherit (cfg.network) hostAddress localAddress;
          # secrets at the same paths as on the host; read when the container
          # starts, restart it after changing one
          bindMounts =
            lib.genAttrs
              [
                "/run/librechat"
                cfg.envFile
                cfg.secrets.credsKey
                cfg.secrets.credsIv
                cfg.secrets.jwtSecret
                cfg.secrets.jwtRefreshSecret
                cfg.secrets.meiliMasterKey
                cfg.secrets.litellmMasterKey
                cfg.secrets.litellmMasterKeyEnvFile
              ]
              (_: {
                isReadOnly = true;
              });
          specialArgs = {
            librechatCfg = cfg;
          };
          # what depends on the host's config
          config = {
            # containers only get nixos' own modules
            imports = [
              ../librechat-rag-api
              ./container.nix
            ];
            nixpkgs.pkgs = pkgs;
            networking.nameservers = [ cfg.network.hostAddress ];
            # owns the bind mounted /run/librechat
            users.users.librechat.uid = config.users.users.librechat.uid;
            users.groups.librechat.gid = config.users.groups.librechat.gid;
            services.litellm.environmentFile = cfg.secrets.litellmMasterKeyEnvFile;
          };
        };

        nixpkgs.allowUnfree = {
          enable = true;
          packages = [ pkgs.mongodb-ce ];
        };

        # egress, and dns through the host's resolved
        networking.nat = {
          enable = true;
          internalInterfaces = [ "ve-librechat" ];
          # masquerade only out the uplink, so tailnet peers can't answer the container
          # (tailscaled's own 100.100.100.100 still does)
          externalInterface = cfg.network.externalInterface;
        };
        assertions = [
          {
            assertion = cfg.network.externalInterface != null;
            message = "infra.librechat.network.externalInterface must be set, otherwise the container would be NATed onto the tailnet";
          }
        ];
        services.resolved.settings.Resolve.DNSStubListenerExtra = [ cfg.network.hostAddress ];
        networking.firewall.interfaces.ve-librechat = {
          allowedTCPPorts = [ 53 ];
          allowedUDPPorts = [ 53 ];
        };

        infra.acme.certs."${cfg.domain}" = { };
        services.caddy = {
          enable = true;
          virtualHosts."${cfg.domain}" = {
            listenAddresses = cfg.network.listenAddresses;
            useACMEHost = cfg.domain;
            extraConfig = ''
              reverse_proxy ${cfg.network.localAddress}:${toString cfg.port} {
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

        infra.restic.backups.librechat = lib.mkIf (cfg.backup.enable && config.infra.restic.enable) (
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
          }
        );

        networking.firewall.interfaces.tailscale0 = lib.mkIf config.services.tailscale.enable {
          allowedTCPPorts = [
            80
            443
          ];
          allowedUDPPorts = [ 443 ];
        };
      };
    };

  ctx.nixos =
    {
      lib,
      config,
      ctx,
      registry,
      ...
    }:
    let
      librechat = ctx.services.librechat or { enable = false; };
    in
    lib.mkIf librechat.enable {
      # nixpkgs' litellm only takes an env file
      sops.templates."librechat-litellm.env".content =
        "LITELLM_MASTER_KEY=${librechat.secrets.litellm-master-key.ph}\n";

      infra.librechat = {
        enable = true;
        domain = lib.mkDefault librechat.domain;
        port = lib.mkDefault librechat.port;
        configFile = lib.mkDefault librechat.config-path;
        envFile = lib.mkDefault librechat.env.path;
        secrets = {
          credsKey = lib.mkDefault librechat.secrets.creds-key.path;
          credsIv = lib.mkDefault librechat.secrets.creds-iv.path;
          jwtSecret = lib.mkDefault librechat.secrets.jwt-secret.path;
          jwtRefreshSecret = lib.mkDefault librechat.secrets.jwt-refresh-secret.path;
          meiliMasterKey = lib.mkDefault librechat.secrets.meili-master-key.path;
          litellmMasterKey = lib.mkDefault librechat.secrets.litellm-master-key.path;
          litellmMasterKeyEnvFile = lib.mkDefault config.sops.templates."librechat-litellm.env".path;
        };
        wif = {
          openbaoUrl = lib.mkDefault registry.openbao.url;
          roleIdFile = lib.mkDefault librechat.wif.role-id.path;
          secretIdFile = lib.mkDefault librechat.wif.secret-id.path;
          vertexServiceAccount = lib.mkDefault librechat.wif.vertex-service-account;
        };
        network = {
          externalInterface = lib.mkDefault ctx.network.interface;
          listenAddresses = lib.mkDefault ctx.tailscale.ips;
        };
      };
    };
}
