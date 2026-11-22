{
  config,
  lib,
  pkgs,
  ...
}:
let
  srv = config.infra.server;
  toplevel = config.system.topLevel;
  closure = pkgs.closureInfo { rootPaths = [ toplevel ]; };
  secretList = lib.attrValues config.sops.secrets;
  secretPaths = pkgs.writeText "current-secrets" (
    lib.concatMapStrings (s: "/var/lib/secrets/${lib.removePrefix "/run/secrets/" s.path}\n") secretList
  );
  decryptSecrets = lib.concatMapStringsSep "\n" (
    s:
    lib.escapeShellArgs [
      "decrypt_secret"
      s.mode
      (lib.removePrefix "/run/secrets/" s.path)
      (toString s.sopsFile)
      (if s.format == "binary" then "" else s.key)
    ]
  ) secretList;

  # Runs on the target as root after the tarball is extracted.
  remoteActivate = ''
    set -eu
    profiles=/nix/var/nix/profiles
    die() { echo "$*" >&2; exit 1; }

    # The prune steps below are destructive; refuse to run without a complete manifest.
    [ -s "$profiles/current-store-paths" ] || die "missing current-store-paths"
    [ -f "$profiles/current-secrets" ] || die "missing current-secrets"
    grep -Fxq ${toplevel} "$profiles/current-store-paths" || die "toplevel not in manifest"

    ${toplevel}/bin/switch-to-configuration switch
    ln -sfn ${toplevel} "$profiles/system"

    prune_store() {
      for p in /nix/store/*; do
        [ -e "$p" ] || continue
        grep -Fxq "$p" "$profiles/current-store-paths" || rm -rf "$p"
      done
      [ -d /nix/store/.links ] && find /nix/store/.links -links 1 -delete || true
    }

    prune_secrets() {
      [ -d /var/lib/secrets ] || return 0
      find /var/lib/secrets -type f | while IFS= read -r f; do
        grep -Fxq "$f" "$profiles/current-secrets" || rm -f "$f"
      done
      find /var/lib/secrets -depth -mindepth 1 -type d -empty -delete 2>/dev/null || true
    }

    prune_store
    prune_secrets
    echo "activated ${toplevel}"
  '';

  # Runs over ssh on every deploy (login shell): elevates, extracts the tarball from stdin, then runs `remoteActivate`.
  remoteEntrypoint = ''
    set -eu
    [ -e /etc/NIXOS ] || [ -e /nix/var/nix/profiles/system ] || {
      echo "ERROR: target is not bootstrapped (not NixOS/Finix); use .#bootstrap.images.<name> instead of deploy" >&2
      exit 1
    }
    export PATH=/run/current-system/sw/bin:/bin:/sbin
    if [ "$(id -u)" -eq 0 ]; then
      run_root() { "$@"; }
    elif [ -x /var/lib/wrappers/bin/sudo ]; then
      run_root() { /var/lib/wrappers/bin/sudo "$@"; }
    else
      run_root() { /run/wrappers/bin/sudo "$@"; }
    fi
    run_root mkdir -p /nix/store /nix/var/nix/profiles /var/lib/secrets
    run_root tar -xf - -C /
    run_root sh -c ${lib.escapeShellArg remoteActivate}
  '';
in
{
  config.system.build.deploy = pkgs.writeShellApplication {
    name = "deploy-mini-${srv.hostname}";
    runtimeInputs = with pkgs; [
      sops
      gnutar
      openssh
      coreutils
    ];
    text = ''
      if [ $# -gt 0 ] && [ "''${1#-}" = "$1" ]; then
        target=$1
        shift
      else
        echo "usage: deploy-mini-${srv.hostname} <user@host> [ssh-opts...]" >&2
        exit 1
      fi

      umask 077
      work=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}")
      trap 'rm -rf "$work"' EXIT

      stage_profile() {
        install -D -m 0644 "$1" "$work/root/nix/var/nix/profiles/$2"
      }

      decrypt_secret() {
        local mode=$1 rel=$2 file=$3 key=$4
        local dst="$work/root/var/lib/secrets/$rel"
        (umask 026; mkdir -p "$(dirname "$dst")")
        if [ -z "$key" ]; then
          sops decrypt --input-type binary --output-type binary "$file" > "$dst"
        else
          sops decrypt --extract "[\"$key\"]" --output-type binary "$file" > "$dst"
        fi
        chmod "$mode" "$dst"
      }

      fetch_missing_paths() {
        ssh "$@" "$target" '
          while IFS= read -r p; do
            [ -n "$p" ] || continue
            [ -e "$p" ] || printf "%s\n" "''${p#/}"
          done
        ' < ${closure}/store-paths
      }

      install -d -m 0755 \
        "$work/root" \
        "$work/root/var" "$work/root/var/lib" \
        "$work/root/nix" "$work/root/nix/var" "$work/root/nix/var/nix" "$work/root/nix/var/nix/profiles"
      install -d -m 0751 "$work/root/var/lib/secrets"

      stage_profile ${closure}/store-paths current-store-paths
      stage_profile ${secretPaths} current-secrets
      ${decryptSecrets}

      fetch_missing_paths "$@" > "$work/missing-paths"
      missing_count=$(wc -l < "$work/missing-paths")
      echo "deploy-mini-${srv.hostname}: syncing $missing_count new store path(s) to $target..." >&2

      env_prefix=""
      [ "''${NIXOS_NO_CHECK:-}" = 1 ] && env_prefix="export NIXOS_NO_CHECK=1; "
      tar --owner=0 --group=0 --numeric-owner -cf - -C "$work/root" . -C / -T "$work/missing-paths" \
        | ssh "$@" "$target" "''${env_prefix}"${lib.escapeShellArg remoteEntrypoint}
    '';
  };
}
