{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.infra.alerts;
in
{
  options.infra.alerts = {
    enable = lib.mkEnableOption "failure alerts to ntfy";
    url = lib.mkOption {
      type = lib.types.str;
      description = "ntfy server base url";
    };
    topic = lib.mkOption {
      type = lib.types.str;
    };
    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = "this host's write-only ntfy token";
    };
    units = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "services whose failure is sent (OnFailure)";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services = {
      # %i: the failed unit (not %I, which turns its dashes into slashes), from OnFailure=notify-failure@%n.service
      "notify-failure@" = {
        description = "Send the failure of %i to ntfy";
        scriptArgs = "%i";
        path = [
          pkgs.curl
          config.systemd.package
        ];
        script = ''
          unit=$1
          journalctl -u "$unit" -n 20 --no-pager -o cat |
            curl -fsS --retry 5 --retry-all-errors --max-time 30 \
              -H @<(printf 'Authorization: Bearer %s' "$(< "$CREDENTIALS_DIRECTORY/token")") \
              -H "Title: ${config.networking.hostName}: $unit failed" \
              -H "Priority: high" \
              -H "Tags: warning" \
              --data-binary @- \
              ${lib.escapeShellArg "${cfg.url}/${cfg.topic}"}
        '';
        serviceConfig = {
          Type = "oneshot";
          DynamicUser = true;
          SupplementaryGroups = [ "systemd-journal" ];
          LoadCredential = "token:${cfg.tokenFile}";
        };
      };
    }
    // lib.genAttrs cfg.units (_: {
      unitConfig.OnFailure = [ "notify-failure@%n.service" ];
    });
  };
}
