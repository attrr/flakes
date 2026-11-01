---
trigger: always_on
---

# Flake Directory Architecture

When writing or modifying code in this repository, rigidly adhere to the following directory purposes:

- **`hosts/<hostname>/`**: Machine-specific configuration (disks, network quirks, its own services). Every ctx host gets a `nixosConfigurations` entry (and a `deploy.nodes` one, from its ctx `deploy`); `hosts/<host>/default.nix` is added when it exists, so only create the directory for real overrides. `hosts/<host>/default-<variant>.nix` adds a `<host>+<variant>` config with the same ctx entry (same identity). Never edit the host list in `flake.nix`.
- **`modules/ctx/`**: Glue from `ctx` into the pure modules; the only modules (besides `hosts/`) allowed to read `ctx`. `flake.nix` (`mkSystem`) adds them from the host's ctx entry, so hosts never import them: `host.nix` and `proxy.nix` (gated on the proxy services) for every host, `<tag>.nix` for each tag in `metadata.tags`, `providers/<provider>.nix` for `metadata.provider`. Anything derivable from ctx goes here as `lib.mkDefault`.
- **`modules/module-list.nix`**: Option modules, inert until enabled (`nixosModules.default`, in every host). Their options live under `infra.*` (our opinionated wrappers: `infra.disko`, `infra.sing-box`, ...; profiles put their knobs there too, e.g. `infra.server`); standalone services follow upstream naming (`services.<name>`). Never import them by path.
- **`modules/profiles/`**: Opinionated config, applied by import like nixpkgs profiles. `profiles/<tag>` is imported by `mkSystem` for each ctx tag (`server`, `desktop`); `base` is pulled in by those. Hardware profiles (`modules/hardware/`) are imported by the host.
- **`modules/*` (except `ctx`)**: Pure NixOS modules. Code here MUST NOT reference `ctx`.
- **Host-private options**: Options declared inside `hosts/<host>/` live under `<host>.*` (e.g. `yata.sing-box`).
- **`lib/*`**: Helpers for host configs, exposed as the `helpers` module arg (not ctx's `fn`). They should only depend on `lib` and not system configuration or context.
- **`pkgs/`**: Contains custom derivations and software packages built from source via `callPackage`.
- **`bootstrap/`**: Install-time artifacts only (`legacyPackages.<system>.bootstrap`): the RAM rescue initrd (`rescue.<host>`, configured from `ctx` via `bootstrap/ctx.nix`, per-host tweaks in `bootstrap/hosts/<host>.nix`) and flashable images (`images.<name>`). Never import anything from here into `nixosConfigurations`.
