---
name: verify-flakes
description: Verify NixOS/finix host evaluations, Home Manager configs, nixd completion (eval-modules.nix), and ctx schema/secrets integrity after changes in flakes or ctx.
---

# Verify Flakes & ctx

Run these checks after modifying modules, profiles, `flake.nix`, or `ctx`.

## 1. Track New Files Before Pure Eval

Nix flakes (`git+file://` / `.#`) ignore untracked files. Before running flake evaluations on new files:

```sh
git add -N <new-files>
# and inside ctx if ctx has new files:
git -C ctx add -N <new-ctx-files>
```

## 2. Verify `ctx` (When `ctx/` Changed)

1. Check schema/vars consistency (must report 0 errors):
   ```sh
   nix run path:./ctx -- check
   ```
2. When refactoring `ctx` without changing outputs, snapshot and diff before/after:
   ```sh
   nix eval --json path:./ctx#inventory.x86_64-linux > /tmp/inv.json
   nix eval --json path:./ctx#cluster.registry > /tmp/reg.json
   ```
   (Avoid evaluating raw `ctx#cluster.hosts` directly—some generator options require `pkgs` only available inside generator scripts.)

## 3. Verify `flakes` Evaluations

Evaluate all NixOS + finix hosts, Home Manager configs, and `eval-modules.nix` (used by `nixd`):

```sh
nix eval --json --impure --expr 'let f = builtins.getFlake "path:${toString ./.}"; in {
  hosts = builtins.mapAttrs (_: c: c.config.system.build.toplevel.drvPath) f.nixosConfigurations;
  homes = builtins.mapAttrs (_: h: h.activationPackage.drvPath) f.homeConfigurations;
}'
```

Verify `eval-modules.nix` (`nixd` completion):

```sh
nix eval --impure --json --expr 'let m = import ./eval-modules.nix; in builtins.mapAttrs (_: v: builtins.length (builtins.attrNames v)) m'
```

For zero-regression refactors, save the `drvPath` JSON before and after and diff them.

## 4. Format & Flake Checks

1. Format `.nix` files with `nix fmt` (or `nixfmt`).
2. Run flake checks (verifies `nixfmt`, `deadnix`, pure `nixosModules.default` without `ctx`, `nixos.container` profile, and `deploy-rs` schema):
   ```sh
   nix flake check --no-build
   # or build the lightweight checks directly:
   nix build .#checks.x86_64-linux.format .#checks.x86_64-linux.deadnix .#checks.x86_64-linux.pure-nixos-modules .#checks.x86_64-linux.nixos-container-profile --no-link
   ```
