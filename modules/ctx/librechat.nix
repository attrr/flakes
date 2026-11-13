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
  sops.secrets."${librechat.wif.role-id.name}".owner = "librechat";
  sops.secrets."${librechat.wif.secret-id.name}".owner = "librechat";

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
}
