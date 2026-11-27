{
  config,
  ctx,
  lib,
  pkgs,
  ...
}:
let
  forgejo = ctx.services.forgejo;
  forgejoCfg = config.services.forgejo;
  runnerTokenFile = "${forgejoCfg.stateDir}/runner-token.env";
  localUrl = "http://127.0.0.1:${toString forgejo.port}";
  publicUrl = "https://${forgejo.domain}";
in
{
  infra.containers.enable = true;

  services.forgejo = {
    enable = true;
    package = pkgs.forgejo;
    database.type = "sqlite3";
    lfs.enable = true;
    settings = {
      server = {
        DOMAIN = forgejo.domain;
        ROOT_URL = "${publicUrl}/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = forgejo.port;
        START_SSH_SERVER = true;
        SSH_USER = "git";
        BUILTIN_SSH_SERVER_USER = "git";
        SSH_LISTEN_PORT = forgejo.ssh-port;
        SSH_PORT = forgejo.ssh-port;
      };
      service.DISABLE_REGISTRATION = true;
      session.COOKIE_SECURE = true;
      actions = {
        ENABLED = true;
        DEFAULT_ACTIONS_URL = "github";
      };
    };
  };

  infra.acme.certs.${forgejo.domain} = { };

  services.caddy = {
    enable = true;
    virtualHosts.${forgejo.domain} = {
      listenAddresses = ctx.tailscale.ips;
      useACMEHost = forgejo.domain;
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString forgejo.port}
      '';
    };
  };

  networking.firewall.interfaces.tailscale0 = lib.mkIf config.services.tailscale.enable {
    allowedTCPPorts = [ forgejo.ssh-port ];
  };

  virtualisation.podman.dockerSocket.enable = true;

  systemd.services.forgejo-runner-token = {
    description = "Generate Forgejo Actions runner registration token";
    after = [ "forgejo.service" ];
    requires = [ "forgejo.service" ];
    before = [
      "gitea-runner-nix.service"
      "gitea-runner-podman.service"
    ];
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "!${runnerTokenFile}";
    environment = {
      GITEA_WORK_DIR = forgejoCfg.stateDir;
      GITEA_CUSTOM = forgejoCfg.customDir;
    };
    serviceConfig = {
      Type = "oneshot";
      User = forgejoCfg.user;
      Group = forgejoCfg.group;
      UMask = "0077";
    };
    script = ''
      set -euo pipefail
      ready=0
      for _ in $(seq 1 30); do
        if ${lib.getExe pkgs.curl} -fsS ${lib.escapeShellArg "${localUrl}/api/healthz"} >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 1
      done
      [ "$ready" -eq 1 ]

      token=$(${lib.getExe forgejoCfg.package} forgejo-cli \
        --work-path ${lib.escapeShellArg forgejoCfg.stateDir} \
        --config ${lib.escapeShellArg "${forgejoCfg.customDir}/conf/app.ini"} \
        actions generate-runner-token | tail -n1)
      [ -n "$token" ]

      tmp=$(mktemp ${lib.escapeShellArg "${runnerTokenFile}.XXXXXX"})
      printf 'TOKEN=%s\n' "$token" > "$tmp"
      mv "$tmp" ${lib.escapeShellArg runnerTokenFile}
    '';
  };

  services.gitea-actions-runner = {
    package = pkgs.forgejo-runner;
    instances = {
      nix = {
        enable = true;
        name = "${ctx.metadata.hostname}-nix";
        url = publicUrl;
        tokenFile = runnerTokenFile;
        labels = [ "nix:host" ];
        hostPackages = with pkgs; [
          bash
          config.nix.package
          coreutils
          curl
          gawk
          git
          gitleaks
          gnused
          jq
          nodejs
          python3
          wget
        ];
      };

      podman = {
        enable = true;
        name = "${ctx.metadata.hostname}-podman";
        url = publicUrl;
        tokenFile = runnerTokenFile;
        labels = [
          "ubuntu-latest:docker://code.forgejo.org/oci/node:22-bookworm"
          "debian-latest:docker://code.forgejo.org/oci/node:22-bookworm"
        ];
        settings.container.network = "host";
      };
    };
  };

  nix.settings.allowed-users = [ "gitea-runner" ];

  systemd.services.gitea-runner-nix = {
    after = [ "forgejo-runner-token.service" ];
    wants = [ "forgejo-runner-token.service" ];
    environment.NIX_PREWARM_GCROOT_DIR = "/var/lib/gitea-runner/nix/prewarm";
    serviceConfig = {
      TimeoutStartSec = "30s";
      Nice = 19;
      IOSchedulingClass = "idle";
      MemoryHigh = "5G";
      MemoryMax = "6G";
    };
  };

  systemd.services.gitea-runner-podman = {
    after = [ "forgejo-runner-token.service" ];
    wants = [ "forgejo-runner-token.service" ];
    serviceConfig = {
      TimeoutStartSec = "30s";
      Nice = 19;
      IOSchedulingClass = "idle";
    };
  };

  infra.restic.backups.forgejo =
    let
      dbBackup = "/var/lib/forgejo-db-backup";
    in
    {
      paths = [
        dbBackup
        forgejoCfg.stateDir
      ];
      exclude = [
        "${forgejoCfg.stateDir}/data/forgejo.db*"
        "${forgejoCfg.stateDir}/data/tmp"
        "${forgejoCfg.stateDir}/data/indexers"
        "${forgejoCfg.stateDir}/data/queues"
        "${forgejoCfg.stateDir}/data/actions_log"
        "${forgejoCfg.stateDir}/data/actions_artifacts"
        "${forgejoCfg.stateDir}/data/repo-archive"
        "${forgejoCfg.stateDir}/dump"
        "${forgejoCfg.stateDir}/log"
      ];
      backupPrepareCommand = ''
        rm -rf ${dbBackup}
        mkdir -p ${dbBackup}
        ${pkgs.sqlite}/bin/sqlite3 -cmd ".timeout 10000" \
          ${lib.escapeShellArg "${forgejoCfg.stateDir}/data/forgejo.db"} \
          ".backup '${dbBackup}/forgejo.db'"
      '';
      backupCleanupCommand = ''
        rm -rf ${dbBackup}
      '';
    };
}
