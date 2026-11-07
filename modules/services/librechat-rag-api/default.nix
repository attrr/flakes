{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.librechat-rag-api;
  name = "librechat-rag-api";
  pg = config.services.postgresql.package;
in
{
  options.services.librechat-rag-api = {
    enable = lib.mkEnableOption "LibreChat's RAG API, on a local socket-only postgres";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.librechat-rag-api;
      description = "The librechat-rag-api package to use.";
    };

    listen = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:8000";
      description = "Address the API listens on, via socket activation (ListenStream=).";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        EMBEDDINGS_PROVIDER = "vertexai";
        EMBEDDINGS_MODEL = "gemini-embedding-001";
      };
      description = "Non-secret environment, see rag_api's README.";
    };

    jwtSecretFile = lib.mkOption {
      type = lib.types.path;
      description = "File holding LibreChat's JWT_SECRET, the bare value; requests are verified with it.";
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Other secret environment, e.g. an embeddings provider's api key.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql = {
      enable = true;
      extensions = ps: [ ps.pgvector ];
      ensureDatabases = [ name ];
      ensureUsers = [
        {
          inherit name;
          ensureDBOwnership = true;
        }
      ];
    };

    systemd.sockets.${name} = {
      description = "LibreChat RAG API socket";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ cfg.listen ];
    };

    systemd.services.${name} = {
      description = "LibreChat RAG API";
      # setup, where ensureDatabases/ensureUsers run
      requires = [ "postgresql-setup.service" ];
      after = [
        "postgresql-setup.service"
        "network-online.target"
      ];
      wants = [ "network-online.target" ];

      environment = {
        # peer auth as the dynamic user, the password is never checked
        POSTGRES_USE_UNIX_SOCKET = "true";
        DB_HOST = "/run/postgresql";
        POSTGRES_DB = name;
        POSTGRES_USER = name;
        POSTGRES_PASSWORD = "unused";
        RAG_UPLOAD_DIR = "/var/lib/${name}/uploads/";
        HOME = "/var/lib/${name}";
      }
      // cfg.environment;

      serviceConfig = {
        # vector isn't a trusted extension, the owner can't create it
        ExecStartPre = "+${pkgs.util-linux}/bin/runuser -u postgres -- ${pg}/bin/psql -d ${name} -c 'CREATE EXTENSION IF NOT EXISTS vector'";
        ExecStart = pkgs.writeShellScript "${name}-start" ''
          JWT_SECRET="$(< "$CREDENTIALS_DIRECTORY/jwt-secret")"
          export JWT_SECRET
          exec ${lib.getExe cfg.package} --fd 3
        '';
        LoadCredential = "jwt-secret:${cfg.jwtSecretFile}";
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

        DynamicUser = true;
        User = name;
        StateDirectory = name;
        StateDirectoryMode = "0700";
        UMask = "0077";

        Restart = "on-failure";
        RestartSec = "5s";

        CapabilityBoundingSet = "";
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectHome = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ProtectProc = "invisible";
        LockPersonality = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
      };
    };
  };
}
