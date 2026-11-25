---
trigger: always_on
---

# Flake Directory Architecture

When writing or modifying code in this repository, rigidly adhere to the following directory purposes:

- **`hosts/<hostname>/`**: Machine-specific configuration (disks, network quirks, its own services). Every ctx host gets a `nixosConfigurations` entry (and a `deploy.nodes` one, from its ctx `deploy`); `hosts/<host>/default.nix` is added when it exists, so only create the directory for real overrides. `hosts/<host>/default-<variant>.nix` adds a `<host>+<variant>` config with the same ctx entry (same identity). Never edit the host list in `flake.nix`.
- **`modules/`**: Unified single feature tree resolved via `lib/aspects.nix`. A feature file/dir may export `{ includes, module, ctx }` (or shorthand `{ common, nixos, finix, homeManager }` for pure multi-class modules):
  - **`module`** (or shorthand `common`/`nixos`/`finix`/`homeManager`): Pure module with typed `options` under `infra.*` (or upstream namespaces like `services.<name>` / `nixpkgs.allowUnfree`). MUST NOT reference `ctx` or `sops.secrets`. `modules/default.nix` (`nixosModules.default`) uses `aspectLib.resolveModule "nixos"` so pure modules never pull in `ctx`.
  - **Multi-class mixing**: `common` is loaded for every resolved class (`nixos`, `finix`, `homeManager`), so only put genuinely cross-class declarations there.
  - **`ctx`**: Cluster wiring (`ctx -> infra.*` as `lib.mkDefault`), only loaded by `aspectLib.resolve` during host assembly.
  - **`includes` vs `options`**: Use `includes`/`imports` for static host identity and platform boundaries (`server`, `desktop`, `providers/*`, `hardware/*`); use typed `options` (`enable`, `topology`, `mode`) for configurable or conditional capabilities.
  - **Secrets**: Service modules declare backend-agnostic `infra.secrets.<name>` (including their own runtime `owner`/`group`, accounting for `DynamicUser` when applicable). `modules/secrets.nix` centrally adapts them to `sops.secrets`.
  - **`modules/services/`**: Standardize every service as `<name>/default.nix`.
  - **`modules/finix/`**: finix platform polyfills / upstream-equivalent modules (`compat.nix`, `sops.nix`, `services/sing-box.nix`). Always spell `finix` lowercase.
  - **`modules/profiles/`**: Opinionated profiles (`base`, `server`, `desktop`, `container`, `container-minimal`, `host.nix`). Hardware profiles (`modules/hardware/`) are imported by hosts; provider presets live under `modules/providers/`.
  - `flake.nix` exposes profiles as `self.modules.<class>.<name>` (e.g. `self.modules.nixos.server`, `self.modules.finix.container-minimal`, `self.modules.homeManager.desktop`).
- **Host-private options**: Options declared inside `hosts/<host>/` live under `<host>.*` (e.g. `yata.sing-box`).
- **`lib/*`**: Helpers for host configs, exposed as the `helpers` module arg (not ctx's `fn`). They should only depend on `lib` and not system configuration or context.
- **`pkgs/`**: Contains custom derivations and software packages built from source via `callPackage`.
- **`bootstrap/`**: Install-time artifacts only (`legacyPackages.<system>.bootstrap`): the RAM rescue initrd (`rescue.<host>`, configured from `ctx` via `bootstrap/rescue/ctx.nix`, per-host tweaks in `bootstrap/rescue/hosts/<host>.nix`) and flashable images (`images.<name>`). Never import anything from here into `nixosConfigurations`.
