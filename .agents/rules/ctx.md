# NixOS Flakes Rules

## Context variables (`ctx`)
- `ctx` lives in the `./ctx` git submodule (private repo `attrr/ctx`). This repo is PUBLIC.
- Schema: `ctx/modules/perhost/` (per host) and `ctx/modules/cluster/` (registry, global). Data: `ctx/hosts/<hostname>/`, `ctx/common/`.
- `flake.nix` imports `ctx/flake.nix` and adds `ctx.nixosModules.<hostname>`, which injects `ctx`, `registry` and `global` as module args.
- NEVER copy values from `ctx` (IPs, ports, hostnames, keys, secret names) into files outside `ctx/`. Reference them through `ctx.*` instead.
- Secrets are sops-encrypted files under `ctx/vars/` (made by `vars`); never decrypt them or write plaintext secrets.
- New secrets are declared as `generators` in ctx and created with `nix run ./ctx -- generate` (see ctx/README.md); consume them via `ctx.vars.<gen>.<file>`. Check consistency with `nix run ./ctx -- check`; `-- types` lists generator types.
- Nix only sees files tracked by git: `git -C ctx add` any new file under `ctx/`.
- Committing: commit (and push) inside `ctx` first, then `git add ctx` in this repo to bump the pointer.
