# NixOS Flakes Rules

## Context variables (`ctx`)
- `ctx` lives in the `./ctx` git submodule (private repo `attrr/ctx`). This repo is PUBLIC.
- Schema: `ctx/modules/perhost/` (per host, including unified `services.exitnode` for `vless`/`hysteria2`/`shadowsocks` + `outbound.{type,usque}`) and `ctx/modules/cluster/` (registry, global). Data: `ctx/hosts/<hostname>/`, `ctx/common/`.
- **Data ownership layering**: Machine-generated drifting facts live in `facts.json` (merged at `lib.mkOverride 900`); human overrides live in `default.nix` (normal priority 100, never touched by automation). Never generate or regex-patch `.nix` manifests from scripts.
- `flake.nix` imports `ctx/flake.nix` and adds `ctx.nixosModules.<hostname>`, which injects `ctx`, `registry` and `global` as module args on NixOS/finix hosts. Standalone `homeConfigurations` instead receive read-only `ctx = { global, registry, hosts }` via `extraSpecialArgs` (not perhost `config.ctx`).
- NEVER copy values from `ctx` (IPs, ports, hostnames, keys, secret names) into files outside `ctx/`. Reference them through `ctx.*` instead.
- Secrets are sops-encrypted files under `ctx/vars/` (made by `vars`); never decrypt them or write plaintext secrets.
- New secrets are declared as `generators` in ctx and created with `nix run ./ctx -- generate` (see ctx/README.md); consume them via `ctx.vars.<gen>.<file>`. Check consistency with `nix run ./ctx -- check`; `-- types` lists generator types.
- Nix only sees files tracked by git: `git -C ctx add` any new file under `ctx/`.
- Committing: commit (and push) inside `ctx` first, then `git add ctx` in this repo to bump the pointer.
