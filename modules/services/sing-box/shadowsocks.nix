{ config, lib, ... }:
let
  cfg = config.infra.sing-box.shadowsocks;
in
{
  options.infra.sing-box.shadowsocks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "enable shadowsocks inbound";
    };
    tag = lib.mkOption {
      type = lib.types.str;
      default = "ss";
      description = "shadowsocks inbound tag";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1089;
      description = "port shadowsocks listened to, ipv4 only";
    };
    passwordPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Path to the file containing the Shadowsocks password.";
    };
  };

  config = lib.mkIf (config.infra.sing-box.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> (cfg.passwordPath != "");
        message = "Error: shadowsocks is enable, but passwordPath is missing";
      }
    ];

    infra.sing-box = {
      secrets = [ cfg.passwordPath ];
      tcpPorts = [ cfg.port ];
      udpPorts = [ cfg.port ];
      inbounds = [ cfg.tag ];
    };
    infra.sing-box.settings.inbounds = [
      {
        type = "shadowsocks";
        tag = cfg.tag;
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
