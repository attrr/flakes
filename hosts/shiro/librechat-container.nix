{
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
  litellmConfig = pkgs.writeText "litellm-config.yaml" ''
    model_list:
      - model_name: gemini-3.1-pro-preview
        litellm_params:
          model: vertex_ai/gemini-3.1-pro-preview
          reasoning_effort: high
      - model_name: gemini-3-flash-preview
        litellm_params:
          model: vertex_ai/gemini-3-flash-preview
          reasoning_effort: medium
      - model_name: gemini-3.1-flash-lite-preview
        litellm_params:
          model: vertex_ai/gemini-3.1-flash-lite-preview
          reasoning_effort: medium
      - model_name: gemini-2.5-pro
        litellm_params:
          model: vertex_ai/gemini-2.5-pro
          reasoning_effort: high
      - model_name: gemini-2.5-flash
        litellm_params:
          model: vertex_ai/gemini-2.5-flash
          reasoning_effort: medium
      - model_name: gemini-2.5-flash-lite
        litellm_params:
          model: vertex_ai/gemini-2.5-flash-lite

    litellm_settings:
      drop_params: false
      pass_through_extra_params: true
      timeout: 300
      request_timeout: 300
      stream_timeout: 60
      vertex_ai_safety_settings:
        - category: HARM_CATEGORY_SEXUALLY_EXPLICIT
          threshold: BLOCK_ONLY_HIGH
        - category: HARM_CATEGORY_HATE_SPEECH
          threshold: BLOCK_ONLY_HIGH
        - category: HARM_CATEGORY_HARASSMENT
          threshold: BLOCK_ONLY_HIGH
        - category: HARM_CATEGORY_DANGEROUS_CONTENT
          threshold: BLOCK_ONLY_HIGH
        - category: HARM_CATEGORY_CIVIC_INTEGRITY
          threshold: BLOCK_ONLY_HIGH
  '';
in
{
  systemd.tmpfiles.rules = [
    "C+ /run/librechat/account.json 0640 librechat librechat - ${librechat.wif.vertex-service-account}"
  ];

  environment.etc."containers/systemd/librechat.pod".text = ''
    [Unit]
    Description=LibreChat Pod
    [Pod]
    UserNS=auto
    PublishPort=127.0.0.1:3080:3080
    [Install]
    WantedBy=multi-user.target
  '';

  environment.etc."containers/systemd/lc-meili.container".text = ''
    [Unit]
    Description=LibreChat MeiliSearch
    Requires=librechat-pod.service
    After=librechat-pod.service

    [Container]
    Pod=librechat.pod
    Image=${images.meili}
    Volume=librechat-meili:/meili_data
    Environment=MEILI_HOST=http://127.0.0.1:7700
    Environment=MEILI_NO_ANALYTICS=true
    EnvironmentFile=${librechat.env.path}

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';

  environment.etc."containers/systemd/lc-vector.container".text = ''
    [Unit]
    Description=LibreChat VectorDB (PGVector)
    Requires=librechat-pod.service
    After=librechat-pod.service

    [Container]
    Pod=librechat.pod
    Image=${images.vector}
    Volume=librechat-pg:/var/lib/postgresql/data
    EnvironmentFile=${librechat.env.path}

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';

  environment.etc."containers/systemd/lc-rag.container".text = ''
    [Unit]
    Description=LibreChat RAG API
    Requires=librechat-pod.service
    After=librechat-pod.service lc-vector.service

    [Container]
    Pod=librechat.pod
    Image=${images.rag}
    Volume=/run/librechat:/run/librechat:ro,idmap
    Environment=RAG_PORT=8000
    Environment=RAG_OPENAI_API_KEY=user_provided
    Environment=DB_HOST=127.0.0.1
    Environment=GOOGLE_APPLICATION_CREDENTIALS=/run/librechat/account.json
    EnvironmentFile=${librechat.env.path}

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';

  environment.etc."containers/systemd/lc-mongodb.container".text = ''
    [Unit]
    Description=LibreChat MongoDB
    Requires=librechat-pod.service
    After=librechat-pod.service

    [Container]
    Pod=librechat.pod
    Image=${images.mongo}
    Volume=data-mongo:/data/db
    Exec=mongod --noauth

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';

  # TOFIX: remove this when librechat add WIF support
  environment.etc."containers/systemd/lc-litellm.container".text = ''
    [Unit]
    Description=LibreChat LiteLLM Proxy (Vertex AI)
    Requires=librechat-pod.service
    After=librechat-pod.service

    [Container]
    Pod=librechat.pod
    Image=${images.litellm}
    Volume=${litellmConfig}:/app/config.yaml:ro,idmap
    Volume=/run/librechat:/run/librechat:ro,idmap
    Environment=GOOGLE_APPLICATION_CREDENTIALS=/run/librechat/account.json
    EnvironmentFile=${librechat.env.path}
    Exec=--config /app/config.yaml --port 4000
    HealthCmd=python3 -c 'import urllib.request; urllib.request.urlopen("http://localhost:4000/health/liveliness")'
    HealthInterval=30s
    HealthTimeout=10s
    HealthRetries=3
    HealthStartPeriod=40s

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';

  environment.etc."containers/systemd/lc-api.container".text = ''
    [Unit]
    Description=LibreChat API
    Requires=librechat-pod.service
    After=librechat-pod.service lc-mongodb.service lc-rag.service lc-litellm.service

    [Container]
    Pod=librechat.pod
    Image=${images.api}
    Volume=${librechat.config-path}:/app/librechat.yaml:ro,idmap
    Volume=librechat-images:/app/client/public/images
    Volume=librechat-uploads:/app/uploads
    Volume=librechat-logs:/app/api/logs
    Volume=/run/librechat:/run/librechat:ro,idmap
    Environment=HOST=0.0.0.0
    Environment=NODE_ENV=production
    Environment=MONGO_URI=mongodb://localhost:27017/LibreChat
    Environment=MEILI_HOST=http://localhost:7700
    Environment=RAG_PORT=8000
    Environment=RAG_API_URL=http://localhost:8000
    EnvironmentFile=${librechat.env.path}

    [Service]
    Restart=always

    [Install]
    WantedBy=multi-user.target
  '';

}
