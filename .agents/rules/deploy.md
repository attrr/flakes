---
trigger: always_on
---

# Bootstrap & Deployment Discipline

- **No live bootstrap**: There is no such thing as "live bootstrap" or deploying onto an unbootstrapped host. Initial provisioning, OS takeover, and PID 1 changes happen strictly via `bootstrap/` (rescue initrd or container image) followed by a reboot into the new system.
- **Deploy assumes an already-booted target**: `deploy` (`deploy-rs`, `deploy-mini-*`, `switch-to-configuration`) is only for incremental updates to hosts already running the target OS and init system. Do not write defensive runtime workarounds (e.g., `mkdir -p` duplicating `tmpfiles`, pre-first-boot shims) to handle an imaginary "deploy before first boot" state.
- **Never test boot/PID 1 changes on live hosts**: Any change to PID 1, init scripts, `boot.init`, rootfs takeover (`lustrate`), or early mounts MUST be verified locally (Podman or QEMU VM) first—never push experimental init/boot changes directly to production hosts.
