# Flake apps (`deploy`, `drifting`, `gcroots`).
{
  nixpkgs,
  ctx,
  deploy-rs,
  hosts,
  isContainerMinimal,
}:
system:
let
  lib = nixpkgs.lib;
  pkgs = nixpkgs.legacyPackages.${system};
  selectors = lib.zipAttrsWith (_: lib.concatLists) (
    [ { all = lib.attrNames hosts; } ]
    ++ lib.mapAttrsToList (
      name: h:
      {
        ${name} = [ name ];
      }
      // lib.genAttrs (
        h.metadata.tags
        ++ lib.filter (x: x != null) [
          h.metadata.group
          h.metadata.provider
          (lib.last (lib.splitString "-" name))
        ]
      ) (_: [ name ])
    ) hosts
  );
in
{
  # nix run .#deploy -- [--checks] <selector>... [-- <deploy-rs args>]: a
  # selector is a host, a ctx group, tag or provider, or "all". Skips the
  # flake checks (every host's evaluation) unless --checks
  deploy = {
    type = "app";
    program = toString (
      pkgs.writeShellScript "deploy-selected" ''
        set -euo pipefail
        declare -A sel=(${
          lib.concatStrings (
            lib.mapAttrsToList (
              n: hs: "[${lib.escapeShellArg n}]=${lib.escapeShellArg (toString (lib.unique hs))} "
            ) selectors
          )
        })
        declare -A mini=(${
          lib.concatStrings (
            lib.mapAttrsToList (
              n: h: "[${lib.escapeShellArg n}]=${lib.escapeShellArg "${h.deploy.user}@${h.deploy.hostname}"} "
            ) (lib.filterAttrs (n: _: isContainerMinimal n) hosts)
          )
        })
        targets=()
        checks=(--skip-checks)
        while [ $# -gt 0 ] && [ "$1" != -- ]; do
          if [ "$1" = --checks ]; then
            checks=()
            shift
            continue
          fi
          if [ -z "''${sel[$1]+x}" ]; then
            echo "unknown selector '$1', one of: ''${!sel[*]}" >&2
            exit 1
          fi
          for h in ''${sel[$1]}; do targets+=("$h"); done
          shift
        done
        [ "''${1:-}" = -- ] && shift
        [ ''${#targets[@]} -gt 0 ] || { echo "usage: nix run .#deploy -- [--checks] <selector>... [-- <deploy-rs args>]" >&2; exit 1; }
        mapfile -t targets < <(printf '%s\n' "''${targets[@]}" | sort -u)
        flake="."
        repo_root=$(${pkgs.git}/bin/git rev-parse --show-toplevel 2>/dev/null || pwd)
        if [ -n "$(${pkgs.git}/bin/git -C "$repo_root/ctx" status --porcelain 2>/dev/null || true)" ] \
          || ! ${pkgs.git}/bin/git -C "$repo_root" diff --quiet -- ctx 2>/dev/null; then
          echo "warn: ctx has uncommitted or unbumped changes; using path:$repo_root" >&2
          flake="path:$repo_root"
        fi
        rs_targets=()
        mini_targets=()
        for h in "''${targets[@]}"; do
          if [ -n "''${mini[$h]+x}" ]; then
            mini_targets+=("$h")
          else
            rs_targets+=("$flake#$h")
          fi
        done
        if [ ''${#rs_targets[@]} -gt 0 ]; then
          echo "deploying: ''${rs_targets[*]##*#}" >&2
          ${
            deploy-rs.packages.${system}.default
          }/bin/deploy "''${checks[@]}" --targets "''${rs_targets[@]}" "$@"
        fi
        for h in "''${mini_targets[@]}"; do
          echo "deploying (minimal): $h" >&2
          if [ $# -gt 0 ] && [ "''${1#-}" = "$1" ]; then
            nix run "$flake#nixosConfigurations.$h.config.system.build.deploy" -- "$@"
          else
            nix run "$flake#nixosConfigurations.$h.config.system.build.deploy" -- "''${mini[$h]}" "$@"
          fi
        done
      ''
    );
  };

  # nix run .#drifting -- <subcommand>
  drifting = {
    type = "app";
    program = toString (
      pkgs.writeShellScript "drifting" ''
        exec ${ctx.packages.${system}.default}/bin/vars drifting "$@"
      ''
    );
  };

  # nix run .#gcroots: keep every host's build graph from gc
  gcroots = {
    type = "app";
    program = toString (
      pkgs.writeShellScript "gcroots" ''
        set -e
        roots=''${XDG_STATE_HOME:-$HOME/.local/state}/flakes-gcroots
        rm -rf "$roots"
        mkdir -p "$roots"
        for name in $(nix eval --raw .#nixosConfigurations --apply 'cs: toString (builtins.attrNames cs)'); do
          nix-instantiate --add-root "$roots/$name" --expr \
            "(builtins.getFlake \"$PWD\").nixosConfigurations.\"$name\".config.system.build.toplevel" \
            >/dev/null
          echo "rooted $name"
        done
      ''
    );
  };
}
