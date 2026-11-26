{
  config,
  ctx,
  lib,
  pkgs,
  ...
}:
let
  harmonia = ctx.services.harmonia;
in
{
  boot.binfmt.emulatedSystems = [ "x86_64-linux" ];

  services.harmonia.cache = {
    enable = true;
    signKeyPaths = [ ctx.vars.harmonia-key.secret.path ];
    settings.bind = "127.0.0.1:${toString harmonia.port}";
  };

  infra.acme.certs.${harmonia.domain} = { };

  services.caddy = {
    enable = true;
    virtualHosts.${harmonia.domain} = {
      listenAddresses = ctx.tailscale.ips;
      useACMEHost = harmonia.domain;
      extraConfig = ''
        reverse_proxy 127.0.0.1:${toString harmonia.port}
      '';
    };
  };

  networking.firewall.interfaces.tailscale0 = lib.mkIf config.services.tailscale.enable {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [ 443 ];
  };

  nix.sshServe = {
    enable = true;
    protocol = "ssh-ng";
    trusted = true;
    keys = ctx.services.nix-builder.authorized-keys;
  };

  services.openssh.settings.AllowUsers = [ "nix-ssh" ];

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";
  systemd.services.nix-daemon.serviceConfig = {
    MemoryHigh = "6G";
    MemoryMax = "8G";
  };

  systemd.services.nix-prewarm = lib.mkIf harmonia.prewarm.enable {
    description = "Pre-warm Harmonia binary cache from public flakes repo";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [
      config.nix.package
      git
      coreutils
    ];
    script = ''
      set -euo pipefail
      repo=/var/lib/nix-prewarm/repo
      branch=${lib.escapeShellArg harmonia.prewarm.branch}

      if [ -d "$repo/.git" ]; then
        git -C "$repo" remote set-url origin ${lib.escapeShellArg harmonia.prewarm.repo}
        git -C "$repo" fetch --depth 1 origin "$branch"
        git -C "$repo" reset --hard "origin/$branch"
      else
        git clone --depth 1 --branch "$branch" ${lib.escapeShellArg harmonia.prewarm.repo} "$repo"
      fi

      cd "$repo"
      nix flake update --flake path:.

      for arch in aarch64-linux x86_64-linux; do
        nix build "path:.#legacyPackages.$arch.prewarm" \
          --out-link "/var/lib/nix-prewarm/result-$arch" \
          --max-jobs 1 \
          --cores 2 \
          --keep-going
      done
    '';
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "nix-prewarm";
      Nice = 19;
      IOSchedulingClass = "idle";
      MemoryHigh = "3G";
      MemoryMax = "4G";
    };
  };

  systemd.timers.nix-prewarm = lib.mkIf harmonia.prewarm.enable {
    description = "Daily Harmonia cache pre-warming";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      RandomizedDelaySec = "1h";
      Persistent = true;
    };
  };
}
