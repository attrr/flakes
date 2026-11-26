# AGENTS.md

Repository collaboration conventions for `flakes` (public) + `ctx/` (private submodule).
Architecture, `ctx`, deploy, secrets, and Nix rules live in `.agents/rules/`; reusable workflows live in `.agents/skills/`.

## Collaboration Conventions

- **Align before large edits**: For structural refactors or design trade-offs, present a concise proposal (layout + trade-offs) and confirm before writing files.
- **Minimal diff & zero-regression baseline**: Before refactoring, snapshot baseline `drvPath`s (and `ctx#inventory` / `ctx#cluster.registry` when touching `ctx`) and diff after changes. Avoid opportunistic edits outside the agreed scope and never drop fallback capabilities without asking.
- **Git discipline**:
  - Never run `git commit`, `git push`, or deploy to production hosts unless explicitly requested — and do not suggest or prompt committing.
  - When explicitly asked to commit: use concise single-line Conventional Commits with short path scopes (`h/<host>`, `m/s/<svc>`, `m/p`, `m/ctx`, `pkgs/<pkg>`, `bootstrap`, `flake`, etc.), commit `ctx` before bumping its pointer in `flakes`, never include private domains/internal URLs/`ctx` values in `flakes` commit messages, and check `origin/main` before amending pushed commits.
