# NixOS Flakes Rules

## Context variables (`ctx`)
- NEVER attempt to search for, evaluate, or define the `ctx` attribute set within this repository.
- `ctx` is injected dynamically during evaluation from a separate, secrets repository.
- Treat `ctx` as an externally provided, fully-populated argument in all NixOS modules and `flake.nix` configurations.
- When writing modules (e.g., `modules/ctx/`), simply use `ctx.foo` directly without questioning where `ctx` is defined.
