{ ctx, ... }:
let
  tgu = ctx.services.tgu;
in
{
  sops.secrets."${tgu.env.name}".owner = "tgu";

  services.tgu = {
    enable = tgu.enable;
    environmentFile = tgu.env.path;
    settings = {
      api-id = "$TG_API_ID";
      api-hash = "$TG_API_HASH";
      token = "$TG_BOT_TOKEN";
      gelbooru-api-key = "$GELBOORU_API_KEY";
      gelbooru-user-id = "$GELBOORU_USER_ID";

      user-ids = tgu.whitelist-users;
      channel-ids = tgu.whitelist-channels;
      allow-pedestrian = false;

      daemon = {
        channels = tgu.monitor-channels;
      };
    };
  };
}
