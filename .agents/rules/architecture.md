---
trigger: always_on
---

# Flake Directory Architecture

When writing or modifying code in this repository, rigidly adhere to the following directory purposes:

- **`hosts/<hostname>/`**: Contains concrete, machine-specific Server deployment configuration. Unless a machine has unique overrides, do NOT create a directory for it; simply map it in `flake.nix`.
- **`modules/ctx/`**: Contains server "Profiles". These modules act as glue. They are permitted to consume the global `ctx` attribute set (secrets, network IPs, etc) and inject those values into lower-level modules. Example: `stardust.nix`.
- **`modules/*` (except `ctx`)**: Contains pure NixOS modules. Code here MUST NOT reference `ctx`. It should only define standard `lib.mkOption` blocks and consume `config.*` for generic server configuration.
- **`lib/*`**: Contains pure Nix functions. These functions should only depend on `lib` and not system configuration or context.
- **`pkgs/`**: Contains custom derivations and software packages built from source via `callPackage`.
