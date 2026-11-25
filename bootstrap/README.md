# bootstrap

Install-time artifacts (`legacyPackages.<system>.bootstrap`). Nothing here is imported into `nixosConfigurations`.

```text
legacyPackages.<system>.bootstrap
├── rescue.default   generic RAM rescue initrd (DHCP, ssh_key= on cmdline)
├── rescue.<host>    RAM rescue preconfigured from ctx (+ rescue/hosts/<host>.nix if present)
├── images.<name>    scripts that build a host-identity image into $PWD (or --stdout for tarballs)
└── mkRescue         custom rescue builder
```

## Rescue Initrd (`rescue.<host>`)

Minimal RAM-only NixOS systemd initrd (`sshd`, `zsh`, `dd`, `parted`, `sfdisk`, `zstd`, `grub2`; ~75 MiB RAM):

```sh
nix build .#bootstrap.rescue.<host>
# result/{bzImage,initrd,stage0.initrd,stage1.squashfs}
```

- **Access**: `root`, port `ctx.ssh.ports[0]`, keys from `global.deploy-keys` (or extra `ssh_key="ssh-ed25519 ..."` on kernel cmdline). Host key is ephemeral per boot.
- **kexec from running Linux**:
  ```sh
  scp result/bzImage result/initrd root@<host>:/tmp/
  ssh root@<host> 'kexec -l /tmp/bzImage --initrd=/tmp/initrd --command-line="console=ttyS0 console=tty0" && kexec -e'
  ```
- **Local QEMU check** (`rescue.default` for user-net DHCP):
  ```sh
  qemu-system-x86_64 -enable-kvm -m 512 -nographic \
    -kernel result/bzImage -initrd result/initrd \
    -append "console=ttyS0 ssh_key=\"$(cat ~/.ssh/id_ed25519.pub)\"" \
    -netdev user,id=n,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n
  ```
- **Per-host rescue overrides**: add `bootstrap/rescue/hosts/<host>.nix` (auto-loaded; ctx values use `mkDefault`).

## Identity Images (`images.<name>`)

Generated for every host with `ctx/vars/<host>/ssh-host-key/ssh_host_ed25519_key` (plus `yata` SD image and `flame` repart image). Decrypts host identity (`ssh_host_ed25519_key`, optional `tailscaled.state`) into tmpfs and embeds it so first boot comes up as the host with working sops decryption—no second deploy needed.

```sh
nix run .#bootstrap.images.<name>                   # writes ./<name>.{raw.zst,qcow2,img,tar.gz} (mode 600)
nix run .#bootstrap.images.<name> -- --format qcow2 # disko hosts: raw.zst | qcow2 (<host>+vm defaults to qcow2)
nix run .#bootstrap.images.<name> -- --stdout       # container tarballs: stream directly over SSH
```

- **disko hosts** (`raw.zst` / `qcow2`): stream from rescue onto target disk:
  ```sh
  ssh root@<rescue> 'zstd -dc | dd of=/dev/vda bs=4M status=progress && sync' < <name>.raw.zst
  ssh root@<rescue> reboot
  ```
- **NixOS containers** (`boot.isContainer`, `.tar.gz`): stream onto stock container and switch `/sbin/init` (or `/lib/systemd/systemd` on systemd-based OCI/Podman images):
  ```sh
  nix run .#bootstrap.images.<name> -- --stdout | \
    ssh root@<host> 'tar -xzpf - -C / --numeric-owner && ln -sfn /nix/var/nix/profiles/system/init /sbin/init && sync && reboot'
  ```
- **finix minimal containers** (`drifting` / `container-minimal`, `.tar.gz`): bundles pre-decrypted `/var/lib/secrets/*` (no Nix DB registration). Normally driven via `nix run .#drifting -- bootstrap <name>` (see `ctx/docs/drifting.md`).
- **SD / repart images** (`yata`, `flame`): injects identity into root partition offline via `debugfs`.

### Capturing an Existing Host's Identity

For a new host, declare `credentials.identity.generate = true` (and optionally `tailscale = true`) in `ctx` and run `nix run ./ctx -- generate`. For an existing host:

```sh
nix run ./ctx -- import <host>/ssh-host-key \
  ssh_host_ed25519_key=plain:<(ssh <host> sudo cat /etc/ssh/ssh_host_ed25519_key) \
  ssh_host_ed25519_key.pub=plain:<(ssh <host> cat /etc/ssh/ssh_host_ed25519_key.pub)
nix run ./ctx -- import <host>/tailscale-state \
  tailscaled.state=plain:<(ssh <host> sudo cat /var/lib/tailscale/tailscaled.state)
```

> **Safety**: Outputs contain private keys (mode 600)—keep off shared storage and delete after flashing. Never boot a cloned identity image while the original host is still online.
