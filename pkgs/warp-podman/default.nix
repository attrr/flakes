{ lib, pkgs, ... }:

let
  warpEntrypoint = pkgs.writeShellScriptBin "entrypoint.sh" (builtins.readFile ./entrypoint.sh);
  pkgsWithWarp = import pkgs.path {
    system = pkgs.stdenv.hostPlatform.system;
    config = {
      allowUnfreePredicate =
        pkg:
        builtins.elem (lib.getName pkg) [
          "cloudflare-warp"
        ];
    };
  };
in

pkgs.dockerTools.streamLayeredImage {
  name = "warp";
  tag = "latest";
  contents =
    with pkgs;
    [
      tini
      bashInteractive
      gnugrep
      coreutils
      curl
      jq
      dbus
      sing-box
      cacert
      tzdata # Required for TLS certificate time validation
      iproute2 # Required for WARP to create tun routes
      iptables # Required for WARP routing rules
      dockerTools.fakeNss
      warpEntrypoint

    ]
    ++ [ pkgsWithWarp.cloudflare-warp ];

  extraCommands = ''
    # Map /var/run to /run like standard Linux distributions
    mkdir -p run
    mkdir -p var
    ln -s ../run var/run

    mkdir -p var/lib/dbus
    mkdir -p usr/share
    ln -s ${pkgs.dbus}/share/dbus-1 usr/share/dbus-1

    # SSL Certificates standard paths (WARP looks here)
    mkdir -p etc/ssl/certs
    ln -s ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt etc/ssl/certs/ca-certificates.crt

    # Break the read-only fakeNss symlinks and make writable copies
    rm etc/passwd etc/group
    cp ${pkgs.dockerTools.fakeNss}/etc/passwd etc/passwd
    cp ${pkgs.dockerTools.fakeNss}/etc/group etc/group
    chmod 644 etc/passwd etc/group
    echo "messagebus:x:100:101:dbus:/var/run/dbus:/sbin/nologin" >> etc/passwd    
    echo "messagebus:x:101:" >> etc/group
  '';

  config = {
    Entrypoint = [
      "${pkgs.tini}/bin/tini"
      "--"
      "/bin/entrypoint.sh"
    ];
    Volumes = {
      "/var/lib/cloudflare-warp" = { };
    };
    Healthcheck = {
      Test = [
        "CMD-SHELL"
        "curl -fsS https://cloudflare.com/cdn-cgi/trace | grep -qE 'warp=(plus|on)' || exit 1"
      ];
      Interval = 15000000000; # 15 seconds in nanoseconds
      Timeout = 5000000000; # 5 seconds
      StartPeriod = 30000000000; # 30 seconds
      Retries = 3;
    };
  };
}
