{
  ctx,
  lib,
  pkgs,
  config,
  ...
}:
let
  ntfy = ctx.services.ntfy;
  hashes = {
    alerts = ctx.vars.ntfy-users.alerts;
    receiver = ctx.vars.ntfy-receiver.hash;
  };
  port = toString ntfy.port;
  # host -> credential name; tokens never reach the store
  creds = lib.mapAttrs (host: _: "token-${host}") ntfy.clients;
in
{
  # alerts sink, tailnet only, behind caddy
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url = "https://${ntfy.domain}";
      listen-http = "127.0.0.1:${port}";
      behind-proxy = true;
      auth-default-access = "deny-all";
      auth-users = [
        "alerts:${lib.fileContents hashes.alerts}:user"
        "receiver:${lib.fileContents hashes.receiver}:user"
      ];
      auth-access = [
        "alerts:${ntfy.topic}:wo"
        "receiver:${ntfy.topic}:ro"
      ];
    };
  };

  # ExecStart reads it from /etc, so a changed config alone wouldn't restart it
  systemd.services.ntfy-sh.restartTriggers = [ config.environment.etc."ntfy/server.yml".source ];

  systemd.services.ntfy-sh.serviceConfig = {
    LoadCredential = lib.mapAttrsToList (host: c: "${c}:${ntfy.clients.${host}.path}") creds;
    # every host's token belongs to `alerts`, labelled with the host
    ExecStart = lib.mkForce (
      pkgs.writeShellScript "ntfy-serve" ''
        tok() { printf '%s' "$(< "$CREDENTIALS_DIRECTORY/$1")"; }
        tokens=()
        ${lib.concatStrings (
          lib.mapAttrsToList (host: c: ''
            tokens+=("alerts:$(tok ${c}):${host}")
          '') creds
        )}
        NTFY_AUTH_TOKENS=$(IFS=,; printf '%s' "''${tokens[*]}")
        export NTFY_AUTH_TOKENS
        exec ${config.services.ntfy-sh.package}/bin/ntfy serve -c /etc/ntfy/server.yml
      ''
    );
  };

  # ren's wildcard cert (./default.nix): useACMEHost orders caddy after it and
  # reloads it on renewal. 443 on tailscale0 is opened in ./acme-dns.nix
  services.caddy.virtualHosts.${ntfy.domain} = {
    listenAddresses = ctx.tailscale.ips;
    useACMEHost = ctx.metadata.fdqn;
    extraConfig = ''
      reverse_proxy 127.0.0.1:${port}
    '';
  };
}
