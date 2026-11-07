# the nixos container running librechat, together with what only it talks to
{
  lib,
  pkgs,
  ctx,
  ...
}:
let
  librechat = ctx.services.librechat;
  inherit (librechat) secrets;
in
{
  system.stateVersion = "26.05";

  networking = {
    useHostResolvConf = false;
    firewall.allowedTCPPorts = [ librechat.port ];
  };

  services.mongodb = {
    enable = true;
    package = pkgs.mongodb-ce;
  };
  environment.systemPackages = [ pkgs.mongodb-tools ];

  services.meilisearch = {
    enable = true;
    masterKeyFile = secrets.meili-master-key.path;
    settings.no_analytics = true;
  };

  services.librechat = {
    enable = true;
    # SEARCH, MEILI_HOST, and MEILI_MASTER_KEY from services.meilisearch
    meilisearch.enable = true;
    # third party api keys, referenced by name from librechat.yaml
    credentialsFile = librechat.env.path;
    credentials = {
      CREDS_KEY = secrets.creds-key.path;
      CREDS_IV = secrets.creds-iv.path;
      JWT_SECRET = secrets.jwt-secret.path;
      JWT_REFRESH_SECRET = secrets.jwt-refresh-secret.path;
      LITELLM_MASTER_KEY = secrets.litellm-master-key.path;
    };
    # only what differs from LibreChat's own defaults
    env = {
      HOST = "0.0.0.0";
      # not enableLocalDB: its uri has no database, so the driver's default, test
      MONGO_URI = "mongodb://127.0.0.1:27017/LibreChat";
      PORT = librechat.port;
      NODE_ENV = "production";
      RAG_API_URL = "http://127.0.0.1:8000";
      DEBUG_LOGGING = true;
      # assistants in librechat.yaml, with users' own keys
      ASSISTANTS_API_KEY = "user_provided";

      # accounts are made by hand: email login only, no sign ups or resets
      ALLOW_EMAIL_LOGIN = true;
      ALLOW_REGISTRATION = false;
      ALLOW_SOCIAL_LOGIN = false;
      ALLOW_SOCIAL_REGISTRATION = false;
      ALLOW_PASSWORD_RESET = false;
      # those accounts have no verified email
      ALLOW_UNVERIFIED_EMAIL_LOGIN = true;
      ALLOW_SHARED_LINKS_PUBLIC = false;

      BAN_VIOLATIONS = true;
      LIMIT_CONCURRENT_MESSAGES = true;
      LIMIT_MESSAGE_IP = true;
      # defaults to 1
      ILLEGAL_MODEL_REQ_SCORE = 5;
      # each defaults to 1, these don't count towards a ban
      TTS_VIOLATION_SCORE = 0;
      STT_VIOLATION_SCORE = 0;
      FORK_VIOLATION_SCORE = 0;
      IMPORT_VIOLATION_SCORE = 0;
      FILE_UPLOAD_VIOLATION_SCORE = 0;
    };
  };
  systemd.services.librechat = {
    # the module only renders `settings`, its CONFIG_PATH is read-only
    environment.CONFIG_PATH = lib.mkForce librechat.config-path;
    after = [
      "mongodb.service"
      "litellm.service"
      "librechat-rag-api.socket"
    ];
    wants = [
      "mongodb.service"
      "litellm.service"
      "librechat-rag-api.socket"
    ];
  };

  services.librechat-rag-api = {
    enable = true;
    jwtSecretFile = secrets.jwt-secret.path;
    environment = {
      EMBEDDINGS_PROVIDER = "vertexai";
      EMBEDDINGS_MODEL = "gemini-embedding-001";
      GOOGLE_APPLICATION_CREDENTIALS = "/run/librechat/account.json";
      RAG_OPENAI_API_KEY = "user_provided";
    };
  };

  # FIXME: remove when librechat add vertex wif support
  services.litellm = {
    enable = true;
    port = 4000;
    environment = {
      VERTEXAI_PROJECT = "librechat-conversation";
      VERTEXAI_LOCATION = "global";
      GOOGLE_APPLICATION_CREDENTIALS = "/run/librechat/account.json";
      SCARF_NO_ANALYTICS = "True";
      DO_NOT_TRACK = "True";
      ANONYMIZED_TELEMETRY = "False";
    };
    settings = {
      model_list =
        lib.mapAttrsToList
          (name: cfg: {
            model_name = name;
            litellm_params = {
              model = "vertex_ai/${name}";
            }
            // cfg;
          })
          {
            # FIXME: litellm <=1.87 only detects gemini 3+ via "gemini-3" substring,
            # so reasoning_effort gets mapped to thinkingBudget; rely on the default (high)
            "gemini-4-argon" = { };
            "gemini-3.1-pro-preview".reasoning_effort = "high";
            "gemini-3.8-flash".reasoning_effort = "medium";
            "gemini-3.5-flash-lite".reasoning_effort = "medium";
            "gemini-2.5-pro".reasoning_effort = "high";
            "gemini-2.5-flash".reasoning_effort = "medium";
            "gemini-2.5-flash-lite" = { };
          };

      litellm_settings = {
        drop_params = false;
        pass_through_extra_params = true;
        timeout = 300;
        request_timeout = 300;
        stream_timeout = 60;
        vertex_ai_safety_settings =
          map
            (category: {
              inherit category;
              threshold = "BLOCK_ONLY_HIGH";
            })
            [
              "HARM_CATEGORY_SEXUALLY_EXPLICIT"
              "HARM_CATEGORY_HATE_SPEECH"
              "HARM_CATEGORY_HARASSMENT"
              "HARM_CATEGORY_DANGEROUS_CONTENT"
              "HARM_CATEGORY_CIVIC_INTEGRITY"
            ];
      };
    };
  };

  # account.json, and the bao_jwt it points at
  systemd.services.librechat-rag-api.serviceConfig.SupplementaryGroups = [ "librechat" ];
  systemd.services.litellm.serviceConfig.SupplementaryGroups = [ "librechat" ];
}
