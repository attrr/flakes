---
name: add-feature
description: Scaffold or refactor a multi-class feature/service module in flakes following lib/aspects.nix, infra.secrets, and eval-modules.nix conventions.
---

# Add a Multi-Class Feature or Service

Follow this checklist when adding a new service or cross-class feature under `modules/`.

## 1. Choose Location & Shape

- **Services**: `modules/services/<name>/default.nix`
- **Profiles**: `modules/profiles/<name>/default.nix` (auto-discovered as `self.modules.<class>.<name>` by `modules/default.nix`)
- **Providers**: `modules/providers/<name>.nix`
- **finix polyfills**: `modules/finix/` (only for upstream-equivalent OS primitives missing from `finix`)

Use `{ includes, module, ctx }` (or shorthand `{ common, nixos, finix, homeManager }` when no `ctx` wiring is needed):

```nix
{
  includes = [ ];

  module = {
    common =
      { lib, config, ... }:
      {
        options.infra.<name> = {
          enable = lib.mkEnableOption "<name>";
        };
      };

    nixos =
      { lib, config, ... }:
      lib.mkIf config.infra.<name>.enable {
        # Pure NixOS config; never reference `ctx` or `sops.secrets`
      };

    finix =
      { lib, config, ... }:
      lib.mkIf config.infra.<name>.enable {
        # Pure finix (finit) config; never reference `ctx` or `sops.secrets`
      };
  };

  ctx =
    { lib, ctx, ... }:
    {
      infra.<name> = {
        # Map `ctx.*` into `infra.<name>.*` with `lib.mkDefault`
      };
    };
}
```

### Rules of Thumb
- `common` is loaded for every resolved class (`nixos`, `finix`, `homeManager`): keep it strictly cross-class.
- Prefer typed `options` (`enable`, `mode`, `topology`) for configurable capabilities; reserve `includes` for static host/platform boundaries.
- General extensions to NixOS/HM (like `nixpkgs.allowUnfree`) belong in their upstream namespace rather than `infra.*`.

## 2. Wire Secrets (If Needed)

- Declare generators in `ctx/modules/perhost/` (run `nix run ./ctx -- generate` to materialize encrypted vars).
- In the feature's `module` (OS side), declare backend-agnostic `infra.secrets.<secretName>` with the runtime `owner`/`group`/`mode`/`restartUnits` (check `config.users.users ? <user>` if NixOS uses `DynamicUser`).
- In the feature's `ctx` slot, pass the sops file path (`ctx.vars.<gen>.<file>`) via `infra.<name>.*` or `infra.secrets.<secretName>.sopsFile` with `lib.mkDefault`.
- Never write `sops.secrets` directly in service modules or `ctx` slots—`modules/secrets.nix` adapts `infra.secrets` centrally.

## 3. Register & Update Completion

1. Add the new feature path to `modules/module-list.nix` (for NixOS hosts) and, if applicable, to `modules/profiles/container-minimal/default.nix` (for finix containers).
2. If the feature supports `finix`, add it to `finixModules` in `eval-modules.nix` so `nixd` completion stays in sync.
3. Run the `verify-flakes` workflow before committing.
