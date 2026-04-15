{
  lib,
  ctx,
  pkgs,
  ...
}:
let
  librechat = ctx.services.librechat;
  images = {
    api = "ghcr.io/danny-avila/librechat-dev-api:latest";
    rag = "ghcr.io/danny-avila/librechat-rag-api-dev-lite:latest";
    mongo = "docker.io/library/mongo:8.0.17";
    meili = "docker.io/getmeili/meilisearch:v1.35.1";
    vector = "docker.io/pgvector/pgvector:0.8.0-pg15-trixie";
    litellm = "ghcr.io/berriai/litellm:main-stable";
  };
  litellmConfig = (pkgs.formats.yaml { }).generate "litellm-config.yaml" {
    model_list = lib.mapAttrsToList (name: cfg: {
      model_name = name;
      litellm_params = {
        model = "vertex_ai/${name}";
      } // cfg;
    }) {
      "gemini-3.1-pro-preview".reasoning_effort = "high";
      "gemini-3-flash-preview".reasoning_effort = "medium";
      "gemini-3.1-flash-lite-preview".reasoning_effort = "medium";
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
      vertex_ai_safety_settings = map (category: {
        inherit category;
        threshold = "BLOCK_ONLY_HIGH";
      }) [
        "HARM_CATEGORY_SEXUALLY_EXPLICIT"
        "HARM_CATEGORY_HATE_SPEECH"
        "HARM_CATEGORY_HARASSMENT"
        "HARM_CATEGORY_DANGEROUS_CONTENT"
        "HARM_CATEGORY_CIVIC_INTEGRITY"
      ];
    };
  };
in
{
  imports = [ ../../modules/purpose/quadlet ];

  systemd.tmpfiles.rules = [
    "C+ /run/librechat/account.json 0640 librechat librechat - ${librechat.wif.vertex-service-account}"
  ];

  virtualisation.quadlet = {
    pods.librechat = {
      Unit.Description = "LibreChat Pod";
      Pod = {
        UserNS = "auto";
        PublishPort = "127.0.0.1:3080:3080";
      };
      Install.WantedBy = [ "multi-user.target" ];
    };

    containers = {
      lc-meili = {
        Unit = {
          Description = "LibreChat MeiliSearch";
          Requires = "librechat-pod.service";
          After = "librechat-pod.service";
        };
        Container = {
          Pod = "librechat.pod";
          Image = images.meili;
          Volume = "librechat-meili:/meili_data";
          Environment = [
            "MEILI_HOST=http://127.0.0.1:7700"
            "MEILI_NO_ANALYTICS=true"
          ];
          EnvironmentFile = librechat.env.path;
        };
        Service.Restart = "always";
        Install.WantedBy = [ "multi-user.target" ];
      };

      lc-vector = {
        Unit = {
          Description = "LibreChat VectorDB (PGVector)";
          Requires = "librechat-pod.service";
          After = "librechat-pod.service";
        };
        Container = {
          Pod = "librechat.pod";
          Image = images.vector;
          Volume = "librechat-pg:/var/lib/postgresql/data";
          EnvironmentFile = librechat.env.path;
        };
        Service.Restart = "always";
        Install.WantedBy = [ "multi-user.target" ];
      };

      lc-rag = {
        Unit = {
          Description = "LibreChat RAG API";
          Requires = "librechat-pod.service";
          After = "librechat-pod.service lc-vector.service";
        };
        Container = {
          Pod = "librechat.pod";
          Image = images.rag;
          Volume = "/run/librechat:/run/librechat:ro,idmap";
          Environment = [
            "RAG_PORT=8000"
            "RAG_OPENAI_API_KEY=user_provided"
            "DB_HOST=127.0.0.1"
            "GOOGLE_APPLICATION_CREDENTIALS=/run/librechat/account.json"
          ];
          EnvironmentFile = librechat.env.path;
        };
        Service.Restart = "always";
        Install.WantedBy = [ "multi-user.target" ];
      };

      lc-mongodb = {
        Unit = {
          Description = "LibreChat MongoDB";
          Requires = "librechat-pod.service";
          After = "librechat-pod.service";
        };
        Container = {
          Pod = "librechat.pod";
          Image = images.mongo;
          Volume = "data-mongo:/data/db";
          Exec = "mongod --noauth";
        };
        Service.Restart = "always";
        Install.WantedBy = [ "multi-user.target" ];
      };

      lc-litellm = {
        Unit = {
          Description = "LibreChat LiteLLM Proxy (Vertex AI)";
          Requires = "librechat-pod.service";
          After = "librechat-pod.service";
        };
        Container = {
          Pod = "librechat.pod";
          Image = images.litellm;
          Volume = [
            "${litellmConfig}:/app/config.yaml:ro,idmap"
            "/run/librechat:/run/librechat:ro,idmap"
          ];
          Environment = "GOOGLE_APPLICATION_CREDENTIALS=/run/librechat/account.json";
          EnvironmentFile = librechat.env.path;
          Exec = "--config /app/config.yaml --port 4000";
          HealthCmd = "python3 -c 'import urllib.request; urllib.request.urlopen(\"http://localhost:4000/health/liveliness\")'";
          HealthInterval = "30s";
          HealthTimeout = "10s";
          HealthRetries = 3;
          HealthStartPeriod = "40s";
        };
        Service.Restart = "always";
        Install.WantedBy = [ "multi-user.target" ];
      };

      lc-api = {
        Unit = {
          Description = "LibreChat API";
          Requires = "librechat-pod.service";
          After = "librechat-pod.service lc-mongodb.service lc-rag.service lc-litellm.service";
        };
        Container = {
          Pod = "librechat.pod";
          Image = images.api;
          Volume = [
            "${librechat.config-path}:/app/librechat.yaml:ro,idmap"
            "librechat-images:/app/client/public/images"
            "librechat-uploads:/app/uploads"
            "librechat-logs:/app/api/logs"
            "/run/librechat:/run/librechat:ro,idmap"
          ];
          Environment = [
            "HOST=0.0.0.0"
            "NODE_ENV=production"
            "MONGO_URI=mongodb://localhost:27017/LibreChat"
            "MEILI_HOST=http://localhost:7700"
            "RAG_PORT=8000"
            "RAG_API_URL=http://localhost:8000"
          ];
          EnvironmentFile = librechat.env.path;
        };
        Service.Restart = "always";
        Install.WantedBy = [ "multi-user.target" ];
      };
    };
  };
}
