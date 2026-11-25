---
trigger: glob
globs: "**/*.nix"
---

# Nix Style & Priority Conventions

Conventions not enforced by `nixfmt` / `deadnix` / `lib/checks.nix`:

- **Priority ladder** (keep definitions on distinct tiers so they never collide):
  1. Option `default` (`1500`)
  2. Profile fallback (`lib.mkOverride 1100`, e.g. NixOS container runtime `"lxc"`)
  3. Cluster `ctx` wiring (`lib.mkDefault`, `1000`)
  4. Machine-generated `facts.json` (`lib.mkOverride 900`)
  5. Host hand-written config (`100`)
  6. Hard override (`lib.mkForce`, `50`)
- **Lazy evaluation & guards**: Prefer `lib.mkIf`, `lib.mkMerge`, and `lib.optionalAttrs` over top-level `if ... then ... else` on `config` (avoids infinite recursion). Guard optional backends/users explicitly (`options ? sops`, `config.users.users ? vmagent`).
- **Keep transformations direct**: Avoid unnecessary intermediate conversions (`split` + `combine`, redundant `let` wrappers) when direct `lib.mapAttrs` / `lib.filterAttrs` suffices.
