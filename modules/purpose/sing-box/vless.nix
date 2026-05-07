{ config, lib, ... }:
let
  cfg = config.core.server.sing-box.vless;
in
{
  options.core.server.sing-box.vless = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "enable vless inbound";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 443;
      description = "port vless listened to";
    };
    serverName = lib.mkOption {
      type = lib.types.str;
      default = "nodejs.org";
      description = "vless target server name";
    };

    uuidPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        path to the file containing the VLESS UUID.
        generate via: `sing-box generate uuid`
      '';
    };
    privateKey = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        path to the file containing the REALITY private key (base64 string).
        generate a keypair via: `sing-box generate reality-keypair`
      '';
    };
    shortIdPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = ''
        path to the file containing the REALITY short ID.
        generate an 8-byte hex string via: `sing-box generate rand --hex 8`
      '';
    };
  };

  config = lib.mkIf (config.core.server.sing-box.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> (cfg.uuidPath != "" && cfg.privateKey != "" && cfg.shortIdPath != "");
        message = "Error: vless is enable, but required field is missing";
      }
    ];

    core.server.sing-box = {
      secrets = [
        cfg.privateKey
        cfg.shortIdPath
        cfg.uuidPath
      ];
      tcpPorts = [ cfg.port ];
    };
    core.server.sing-box.settings.inbounds = [
      {
        type = "vless";
        tag = "vls";
        listen = "::";
        listen_port = cfg.port;
        tcp_fast_open = true;
        users = [
          {
            uuid._secret = cfg.uuidPath;
            flow = "xtls-rprx-vision";
          }
        ];
        tls = {
          enabled = true;
          server_name = cfg.serverName;
          reality = {
            enabled = true;
            handshake = {
              server = cfg.serverName;
              server_port = 443;
            };
            private_key._secret = cfg.privateKey;
            short_id = [
              { _secret = cfg.shortIdPath; }
            ];
          };
        };
      }
    ];
  };
}
