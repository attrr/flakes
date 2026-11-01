# bootstrap

Install-time artifacts. Nothing here is imported into `nixosConfigurations`.

```
legacyPackages.<system>.bootstrap
├── rescue.default   generic rescue, DHCP, keys only via ssh_key= on the cmdline
├── rescue.<host>    rescue configured from ctx: port, static network, MAC, hostname
├── images.<name>    flashable images, or scripts that write one into $PWD
└── mkRescue         { modules, specialArgs, kernelPackages } -> rescue
```

## Rescue

A NixOS systemd initrd that never leaves initrd and runs entirely in RAM:
sshd, zsh on every console, and enough tools to wipe and write a disk
(`dd`, `parted`, `sfdisk`, `curl`, `zstd`, `grub2`, ...). About 75 MB of RAM is used after boot.

```sh
nix build .#bootstrap.rescue.<host>
ls result/
# bzImage          kernel
# initrd           stage0 + squashfs merged, the one to use by default
# stage0.initrd    stage0 only, squashfs found on disk (see below)
# stage1.squashfs  the rescue OS
```

### Access

- `rescue.<host>`: root, port `ctx.ssh.ports[0]`, keys from `global.rescue-keys`
  (`ctx/common/default.nix`). These keys are meant for rescue only, never for running hosts.
  The build fails while that list is empty.
- Any variant: extra keys can be added at boot with `ssh_key="ssh-ed25519 AAAA..."` on the
  kernel cmdline (repeatable).
- The host key is generated on every boot, so expect a changed fingerprint:
  `ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null ...`

### Booting it

**kexec from a running Linux** (no provider support needed; the host needs RAM for the ~50 MB initrd):

```sh
scp result/bzImage result/initrd root@host:/tmp/
ssh root@host 'kexec -l /tmp/bzImage --initrd=/tmp/initrd \
  --command-line="console=ttyS0 console=tty0" && kexec -e'
```

**GRUB** (e.g. from the provider's rescue system or an old install):

```
menuentry "rescue" {
  linux  /boot/rescue/bzImage console=ttyS0 console=tty0
  initrd /boot/rescue/initrd
}
```

**Low RAM**: keep the squashfs on disk and boot only the 4 MB stage0, which loop-mounts
it from `root=` + `stage1.path=`. If neither is given, it scans every raw block device.

```
linux  /boot/rescue/bzImage console=ttyS0 root=/dev/vda1 stage1.path=/boot/rescue/stage1.squashfs
initrd /boot/rescue/stage0.initrd
```

**qemu** (to check it locally):

```sh
qemu-system-x86_64 -enable-kvm -m 512 -nographic \
  -kernel result/bzImage -initrd result/initrd \
  -append "console=ttyS0 ssh_key=\"$(cat ~/.ssh/id_ed25519.pub)\"" \
  -netdev user,id=n,hostfwd=tcp:127.0.0.1:2222-:22 -device virtio-net-pci,netdev=n
ssh -p 2222 root@127.0.0.1
```

Hosts with a static network in ctx won't come up under qemu's user net; use `rescue.default` there.

### Installing from it

```sh
ssh root@host 'lsblk'
zstd -c nixos.raw | ssh root@host 'zstd -d | dd of=/dev/vda bs=4M status=progress && sync'
ssh root@host reboot
```

### Kernel cmdline

| param | effect |
|---|---|
| `console=` | a shell is spawned on each; default `ttyS0` + `tty0` |
| `ssh_key="..."` | add an authorized key for root |
| `root=` `stage1.path=` | where stage0 finds the squashfs (stage0.initrd only) |

### Per-host tweaks

Create `bootstrap/hosts/<host>.nix`. It is picked up automatically and is a normal NixOS module
for the rescue initrd:

```nix
{ pkgs, ... }:
{
  rescue.zram.enable = true;          # very low RAM
  rescue.extraPackages = [ pkgs.btrfs-progs ];
  boot.initrd.availableKernelModules = [ "e1000e" ];
}
```

Options: `rescue.ssh.{port,authorizedKeys,hostKeys}`, `rescue.zram.{enable,size}`, `rescue.extraPackages`.

Everything derived from ctx is `mkDefault`, so plain assignments win. Networks:

| file | source |
|---|---|
| `10-*` .. `49-*` | yours, matched before ctx |
| `50-ctx` | ctx static addresses/gateways (only if ctx has any) |
| `99-eth-all` | DHCP on `en* eth*` |

```nix
{
  # tweak the ctx network
  boot.initrd.systemd.network.networks."50-ctx".networkConfig.DHCP = "yes";
  # or replace it for this NIC
  boot.initrd.systemd.network.networks."10-uplink" = {
    matchConfig.Name = "ens18";
    address = [ "192.0.2.10/24" ];
    routes = [ { Gateway = "192.0.2.1"; } ];
  };
}
```

One-off build without a file:

```sh
nix build --impure --expr '(builtins.getFlake "git+file://'$PWD'")
  .legacyPackages.x86_64-linux.bootstrap.mkRescue { modules = [ { rescue.zram.enable = true; } ]; }'
```

## Images with a host identity

Some images must come up as an existing host: same ssh host key (which is also its
sops age key) and same tailscale node (so its tailscale IPs, and everything bound to
them, stay valid). These are scripts instead of derivations:

```sh
nix run .#bootstrap.images.<name>   # writes ./<name>.qcow2
```

They decrypt the host's identity from `ctx/vars/<host>/` with your admin age key into
`$XDG_RUNTIME_DIR`, copy it into the image with disko's `--post-format-files`, and wipe it
on exit. The raw image is built in a temp dir under `$PWD` and converted to a
zstd-compressed qcow2 (`qemu-img convert -O raw` gets a raw one back for `dd`).
Only the encrypted files ever reach the nix store.

| in `ctx/vars/<host>/` | lands at |
|---|---|
| `ssh-host-key/ssh_host_ed25519_key`, `.pub` | `/etc/ssh/` |
| `tailscale-state/tailscaled.state` | `/var/lib/tailscale/` |

- The resulting qcow2 holds private keys (written mode 600): keep it off shared storage.
- Never boot it while the original host is up; they will fight over IP and tailscale node.
- Disable key expiry for the node in the tailscale admin console, or the saved state goes stale.
- The host declares these in ctx: `credentials.identity.generate = true` (the
  `ssh-host-key` generator, admin only) and an admin-only `prompt` generator
  `tailscale-state` with the file `tailscaled.state`. A new host just runs
  `nix run ./ctx -- generate`; an existing one has its identity captured instead
  (plaintext only goes through pipes):

```sh
nix run ./ctx -- import <host>/ssh-host-key \
  ssh_host_ed25519_key=plain:<(ssh <host> sudo cat /etc/ssh/ssh_host_ed25519_key) \
  ssh_host_ed25519_key.pub=plain:<(ssh <host> cat /etc/ssh/ssh_host_ed25519_key.pub)
nix run ./ctx -- import <host>/tailscale-state \
  tailscaled.state=plain:<(ssh <host> sudo cat /var/lib/tailscale/tailscaled.state)
```

## Layout

```
default.nix     outputs, mkRescue, shared kernel module list
identity-image.nix  disko image script carrying a host identity
rescue.nix      stage1: the rescue OS (sshd, console shells, tools, zram)
ctx.nix         ctx -> rescue (keys, port, static addresses/gateways, MAC match)
console.sh      systemd generator: a shell per console= tty
stage0/         busybox init: find squashfs, overlay it, switch_root
hosts/          optional per-host modules
images/         image definitions
```

Boot flow: kernel → stage0 (busybox, modules, ash init) → mount `stage1.squashfs`
(embedded / `root=` partition / raw disk scan, else an emergency shell) → tmpfs overlay → `switch_root`
→ systemd initrd, which is kept from leaving initrd.
