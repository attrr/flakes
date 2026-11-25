---
name: bootstrap-host
description: Provision, reinstall, or take over a NixOS or finix host (standard hosts via bootstrap/ and drifting containers via nix run .#drifting).
---

# Bootstrap a Host

Always follow `.agents/rules/deploy.md` (no "live bootstrap" via `deploy`; verify any PID 1 / init / takeover changes locally in QEMU or Podman first) and `.agents/rules/secrets.md` (never print secret values).

## 1. Identify Host Type

| Host type | Where declared | Tooling | Reference |
|---|---|---|---|
| **Drifting container** (ephemeral NAT / low-RAM `finix` exit node) | `ctx/hosts/drifting/<name>/facts.json` (+ optional `default.nix`), `metadata.minimal = true` | `nix run .#drifting` | `ctx/docs/drifting.md` |
| **disko host** (VPS / bare-metal / VM) | `ctx/hosts/<name>/` + `hosts/<name>/` (`disko.devices.disk`) | `bootstrap.rescue.<host>` + `bootstrap.images.<name>` | `bootstrap/README.md` |
| **NixOS container** | `ctx/hosts/<name>/` (`boot.isContainer`, non-`finix`) | `bootstrap.images.<name> -- --stdout` | `bootstrap/README.md` |
| **SD / repart device** (`yata`, `flame`) | `bootstrap/images/<name>.nix` | `bootstrap.images.<name>` | `bootstrap/README.md` |

## 2. Pre-Flight Checklist

1. **Host identity exists in `ctx`**:
   - New host: `credentials.identity.generate = true` (and `tailscale = true` if needed) in `ctx`, then `nix run ./ctx -- generate`.
   - Existing host: capture keys via `nix run ./ctx -- import <host>/ssh-host-key ...` (pipes only, never print).
   - `bootstrap.images.<name>` is only generated if `ctx/vars/<host>/ssh-host-key/ssh_host_ed25519_key` exists and is tracked by git (`git -C ctx add`).
2. **Never run two copies of the same identity**: do not boot an image while the original host is still online (IP + Tailscale conflict).
3. **Clean up image artifacts**: generated `.raw.zst` / `.qcow2` / `.img` / `.tar.gz` files contain plaintext private keys (mode 600); keep them out of shared storage and delete after flashing.

## 3. Procedures

### A. Drifting Container (`finix`)
Read `ctx/docs/drifting.md` for flags. Standard flow:
1. Optional dry inspect: `nix run .#drifting -- probe <target> -p <port>`
2. Full onboarding (or pass `--no-bootstrap` first if manual `ctx/hosts/drifting/<name>/default.nix` overrides are needed):
   ```sh
   nix run .#drifting -- init <target> -p <port> --provider <p> --loc <loc> --upstream <u> --ports <p1>,<p2>
   ```
3. Re-bootstrap an already-declared host: `nix run .#drifting -- bootstrap <name> [target]`
4. Commit `ctx` first, then bump `ctx` pointer in `flakes`.

### B. disko Host (VPS / Bare-Metal)
1. Build rescue initrd: `nix build .#bootstrap.rescue.<host>` (add `bootstrap/rescue/hosts/<host>.nix` if NIC/driver/zram tweaks are needed).
2. Boot target into rescue via `kexec` from the existing Linux OS (or provider rescue / GRUB):
   ```sh
   scp result/bzImage result/initrd root@<host>:/tmp/
   ssh root@<host> 'kexec -l /tmp/bzImage --initrd=/tmp/initrd --command-line="console=ttyS0 console=tty0" && kexec -e'
   ```
3. Build identity image: `nix run .#bootstrap.images.<name>` (produces `./<name>.raw.zst`, or pass `-- --format qcow2` for VMs).
4. Verify disk name (`lsblk`) in rescue, stream image (`zstd -dc | dd of=/dev/<disk> bs=4M status=progress && sync`), then `reboot`.

### C. NixOS Container (`boot.isContainer`)
1. Check container init entrypoint on the stock OS (`/sbin/init` for LXC, `/lib/systemd/systemd` for systemd-based OCI/Podman images).
2. Stream directly without leaving a tarball on disk:
   ```sh
   nix run .#bootstrap.images.<name> -- --stdout | \
     ssh root@<host> 'tar -xzpf - -C / --numeric-owner && ln -sfn /nix/var/nix/profiles/system/init <entrypoint> && sync && reboot'
   ```
3. After rebooting into NixOS, confirm `systemctl status` and clean up leftover stock OS dirs if needed (preserving the systemd entrypoint symlink on Podman).
