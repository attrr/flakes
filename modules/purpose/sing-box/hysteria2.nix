{ config, lib, ... }:
let
  cfg = config.core.server.sing-box.hysteria2;
in
{
  options.core.server.sing-box.hysteria2 = {
    enable = lib.mkEnableOption "enable hysteria2 inbound";
    port = lib.mkOption {
      type = lib.types.port;
      default = 0;
      description = "port hysteria2 listen, ipv6 only";
    };
    passwordPath = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    tlsKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
    tlsCertificatePath = lib.mkOption {
      type = lib.types.either lib.types.path lib.types.str;
      default = "";
    };
    echKeyPath = lib.mkOption {
      type = lib.types.str;
      default = "";
    };
  };

  config = lib.mkIf (config.core.server.sing-box.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> (cfg.port != 0);
        message = "Error: hysteria2 is enable, but port is missing!";
      }
      {
        assertion =
          cfg.enable -> (
            cfg.passwordPath != ""
            && cfg.tlsKeyPath != ""
            && cfg.tlsCertificatePath != ""
            && cfg.echKeyPath != ""
          );
        message = "Hysteria2 is enabled, but one or more required paths (password, TLS key, TLS cert, or ECH key) are empty!";
      }
    ];

    core.server.sing-box = {
      secrets = [
        cfg.passwordPath
        cfg.tlsKeyPath
        cfg.tlsCertificatePath
        cfg.echKeyPath
      ];
      udpPorts = [ cfg.port ];
    };
    core.server.sing-box.settings.inbounds = [
      {
        type = "hysteria2";
        tag = "hy2";
        # ipv6 only
        listen = "::";
        listen_port = cfg.port;
        up_mbps = 100;
        down_mbps = 100;
        users = [
          {
            name = "whoami";
            password._secret = cfg.passwordPath;
          }
        ];
        tls = {
          enabled = true;
          alpn = [ "h3" ];
          key_path = cfg.tlsKeyPath;
          certificate_path = cfg.tlsCertificatePath;
          ech = {
            enabled = true;
            key_path = cfg.echKeyPath;
          };
        };
      }
    ];
  };

}
