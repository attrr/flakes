---
trigger: always_on
---

# Flake Directory Architecture

When writing or modifying code in this repository, rigidly adhere to the following directory purposes:

- **`hosts/<hostname>/`**: Contains concrete, machine-specific Server deployment configuration. Unless a machine has unique overrides, do NOT create a directory for it; simply map it in `flake.nix`.
- **`modules/ctx/`**: Glue from `ctx` into the pure modules; the only modules (besides `hosts/`) allowed to read `ctx`. `flake.nix` (`mkSystem`) adds them from the host's ctx entry, so hosts never import them: `host.nix` for every host (platform from `metadata.arch`), `profiles/server` + `server.nix` for the `server` tag (hostname, ssh), `proxy.nix` when a proxy service is enabled. Anything derivable from ctx goes here as `lib.mkDefault`; `hosts/` keeps only what is really the machine's own (disks, network quirks, its services). `stardust.nix` is a provider profile on top.
- **`modules/*` (except `ctx`)**: Contains pure NixOS modules. Code here MUST NOT reference `ctx`. It should only define standard `lib.mkOption` blocks and consume `config.*` for generic server configuration.
- **`lib/*`**: Contains pure Nix functions. These functions should only depend on `lib` and not system configuration or context.
- **`pkgs/`**: Contains custom derivations and software packages built from source via `callPackage`.
- **`bootstrap/`**: Install-time artifacts only (`legacyPackages.<system>.bootstrap`): the RAM rescue initrd (`rescue.<host>`, configured from `ctx` via `bootstrap/ctx.nix`, per-host tweaks in `bootstrap/hosts/<host>.nix`) and flashable images (`images.<name>`). Never import anything from here into `nixosConfigurations`.
