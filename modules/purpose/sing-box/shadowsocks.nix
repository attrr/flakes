{ config, lib, ... }:
let
  cfg = config.core.server.sing-box.shadowsocks;
in
{
  options.core.server.sing-box.shadowsocks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "enable shadowsocks inbound";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1089;
      description = "port shadowsocks listened to, ipv4 only";
    };
    passwordPath = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };

  config = lib.mkIf (config.core.server.sing-box.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> (cfg.passwordPath != "");
        message = "Error: shadowsocks is enable, but passwordPath is missing";
      }
    ];

    core.server.sing-box = {
      secrets = [ cfg.passwordPath ];
      tcpPorts = [ cfg.port ];
      udpPorts = [ cfg.port ];
    };
    core.server.sing-box.settings.inbounds = [
      {
        type = "shadowsocks";
        tag = "ss";
        method = "2022-blake3-aes-128-gcm";
        password._secret = cfg.passwordPath;
        listen = "0.0.0.0";
        listen_port = cfg.port;
        multiplex = {
          enabled = true;
        };
      }
    ];
  };
}
