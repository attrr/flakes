{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.core.client.sing-box;
  jsonFormat = pkgs.formats.json { };

in
{
  imports = [
    ./main.nix
    ./outbounds.nix
    ./logic.nix
  ];

  options.core.client.sing-box = {
    enable = lib.mkEnableOption "enable sing-box client";
    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = jsonFormat.type;
      };
      default = { };
    };

    # internal
    tags = lib.mkOption {
      description = "outbound tags per groups";
      internal = true;
      type = lib.types.submodule {
        freeformType = lib.types.attrsOf (lib.types.listOf lib.types.str);
        options = {
          shadowsocks = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          hysteria2 = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          vless = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
        };
      };
    };
  };

  config = lib.mkIf cfg.enable {
    services.sing-box = {
      enable = true;
      settings = cfg.settings;
    };
  };
}
