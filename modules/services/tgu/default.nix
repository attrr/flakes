{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.tgu;
  settingsFormat = pkgs.formats.json { };
in
{
  options.services.tgu = {
    enable = lib.mkEnableOption "tgu daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.tgu;
      description = "The tgu package to use.";
    };

    # Point at a sops-nix (or any) secret file exporting:
    #   TGU_API_ID, TGU_API_HASH, TGU_BOT_TOKEN
    #   TGU_GELBOORU_API_KEY, TGU_GELBOORU_USER_ID  (optional)
    environmentFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to a file containing secret environment variables.";
    };

    settings = lib.mkOption {
      type = settingsFormat.type;
      default = { };
      description = ''
        Contents of config.json, passed verbatim.
        Secret fields (api-id, api-hash, token) should be set to the
        corresponding env-var reference, e.g. "''$TGU_API_ID", which
        the daemon resolves at runtime from environmentFile.
      '';
      example = lib.literalExpression ''
        {
          "api-id"   = "$TGU_API_ID";
          "api-hash" = "$TGU_API_HASH";
          "token"    = "$TGU_BOT_TOKEN";
          "user-ids" = [ 123456789 ];
          daemon = {
            channels      = [ "@my_channel" ];
            sync-interval = 3600;
          };
        }
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.tgu = {
      isSystemUser = true;
      group = "tgu";
    };
    users.groups.tgu = { };

    systemd.services.tgu = {
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        ExecStart = "${cfg.package}/bin/tgu --config ${settingsFormat.generate "tgu-config.json" cfg.settings} daemon";
        EnvironmentFile = cfg.environmentFile;

        User = "tgu";
        Group = "tgu";
        StateDirectory = "tgu";
        StateDirectoryMode = "0700";

        Restart = "on-failure";
        RestartSec = "10s";

        NoNewPrivileges = true;
        PrivateTmp = true;
      };
    };
  };
}
