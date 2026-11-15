---
trigger: always_on
---

# Secrets Handling

- **Never print or expose secrets**: Do not read, `cat`, `jq`, `echo`, or pass literal secret values in tool outputs, command arguments, or responses. This applies to `/run/secrets/*`, rendered runtime configs containing credentials (e.g. `/run/sing-box/config.json`), `.env` files, private keys, API keys, passwords, and tokens.
- **Consume secrets silently**: If a command needs a secret at runtime (such as an authenticated local API call), load it inside the remote shell from its file or environment without printing it, or check non-sensitive fields only.
- **Mandatory rotation on exposure**: If any secret value is accidentally printed into tool output or conversation context, **stop the current task immediately**, notify the user which secret was exposed, and start the rotation flow:
  - For `ctx`-managed secrets: run `nix run ./ctx -- generate --regen <host>/<var>` (or `global/<var>`), redeploy affected hosts, and restart services that load the secret file on startup (e.g. `container@sing-box.service`, `sing-box.service`, `loadbalance.service`).
  - For externally managed credentials (panel API keys, SSH keys, provider tokens): rotate or replace them with the user before resuming.
