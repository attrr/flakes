{
  ctx,
  pkgs,
  ...
}:
let
  envSecret = ctx.vars.fl-watch-env.env;
in
{
  infra.secrets = [
    {
      path = envSecret.path;
      owner = "fl-watch";
    }
  ];

  users.users.fl-watch = {
    isSystemUser = true;
    group = "fl-watch";
  };
  users.groups.fl-watch = { };

  systemd.services.fl-watch = {
    description = "FileList homepage news and shop price watcher";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "fl-watch";
      Group = "fl-watch";
      StateDirectory = "fl-watch";
      EnvironmentFile = envSecret.path;
      ExecStart = "${pkgs.fl-watch}/bin/fl-watch";
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  systemd.timers.fl-watch = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
  };
}
