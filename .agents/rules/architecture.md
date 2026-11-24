---
trigger: always_on
---

# Flake Directory Architecture

When writing or modifying code in this repository, rigidly adhere to the following directory purposes:

- **`hosts/<hostname>/`**: Machine-specific configuration (disks, network quirks, its own services). Every ctx host gets a `nixosConfigurations` entry (and a `deploy.nodes` one, from its ctx `deploy`); `hosts/<host>/default.nix` is added when it exists, so only create the directory for real overrides. `hosts/<host>/default-<variant>.nix` adds a `<host>+<variant>` config with the same ctx entry (same identity). Never edit the host list in `flake.nix`.
- **`modules/`**: Unified single feature tree resolved via `lib/aspects.nix`. A feature file/dir may export `{ includes, module, ctx }` (or shorthand `{ common, nixos, finix }` for pure multi-class modules):
  - **`module`** (or shorthand `common`/`nixos`/`finix`): Pure OS module with typed `options` under `infra.*` (or upstream `services.<name>`). MUST NOT reference `ctx`. `modules/default.nix` (`nixosModules.default`) uses `aspectLib.resolveModule "nixos"` so pure modules never pull in `ctx`.
  - **`ctx`**: Cluster wiring (`ctx -> infra.*` as `lib.mkDefault`), only loaded by `aspectLib.resolve` during host assembly.
  - **`modules/finix/`**: finix platform polyfills / upstream-equivalent modules (`compat.nix`, `sops.nix`, `services/sing-box.nix`).
  - **`modules/profiles/`**: Opinionated profiles (`base`, `server`, `desktop`, `container`, `container-minimal`, `host.nix`). Hardware profiles (`modules/hardware/`) are imported by hosts; provider presets live under `modules/providers/`.
  - `flake.nix` exposes key features as `self.modules.<class>.<name>` (e.g. `self.modules.nixos.server`, `self.modules.nixos.desktop`).
- **Host-private options**: Options declared inside `hosts/<host>/` live under `<host>.*` (e.g. `yata.sing-box`).
- **`lib/*`**: Helpers for host configs, exposed as the `helpers` module arg (not ctx's `fn`). They should only depend on `lib` and not system configuration or context.
- **`pkgs/`**: Contains custom derivations and software packages built from source via `callPackage`.
- **`bootstrap/`**: Install-time artifacts only (`legacyPackages.<system>.bootstrap`): the RAM rescue initrd (`rescue.<host>`, configured from `ctx` via `bootstrap/ctx.nix`, per-host tweaks in `bootstrap/hosts/<host>.nix`) and flashable images (`images.<name>`). Never import anything from here into `nixosConfigurations`.
