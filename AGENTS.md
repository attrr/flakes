# AGENTS.md

Repository collaboration conventions for `flakes` (public) + `ctx/` (private submodule).
Architecture, `ctx`, deploy, secrets, and Nix rules live in `.agents/rules/`; reusable workflows live in `.agents/skills/`.

## Collaboration Conventions

- **Align before large edits**: For structural refactors or design trade-offs, present a concise proposal (layout + trade-offs) and confirm before writing files.
- **Minimal diff & zero-regression baseline**: Before refactoring, snapshot baseline `drvPath`s (and `ctx#inventory` / `ctx#cluster.registry` when touching `ctx`) and diff after changes. Avoid opportunistic edits outside the agreed scope and never drop fallback capabilities without asking.
- **Git discipline**:
  - Check `git status -sb` / `origin/main` before amending commits; prefer a new commit if already pushed unless the user explicitly asks to amend and force-push.
  - Commit `ctx` first, then bump the `ctx` submodule pointer in `flakes`.
  - Never run `git push` or deploy to production hosts unless explicitly requested.
