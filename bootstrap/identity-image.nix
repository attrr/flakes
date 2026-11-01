# Scripts that write an image of a nixos config as an existing host: its ssh
# host key (= sops age key) and tailscale node, from the host's ctx vars
# (<vars> = ctx/vars/<host>; secret files admin-only), are decrypted to tmpfs
# and copied in. Outputs are mode 600 in $PWD: they hold private keys.
#   disko  ./<name>.qcow2 (zstd), from the config's disko image script
#   sd     ./<name>.img, the config's sdImage with the files written into its
#          root partition (ext4, edited offline with debugfs)
{ lib, pkgs }:
let
  # <generator>/<file> -> where it lands; .pub files are public (plain) in vars
  targets = {
    "ssh-host-key/ssh_host_ed25519_key" = "/etc/ssh/ssh_host_ed25519_key";
    "ssh-host-key/ssh_host_ed25519_key.pub" = "/etc/ssh/ssh_host_ed25519_key.pub";
    "tailscale-state/tailscaled.state" = "/var/lib/tailscale/tailscaled.state";
  };
  present = vars: lib.filterAttrs (n: _: builtins.pathExists "${vars}/${n}") targets;
  local = n: "$keys/${baseNameOf n}";
  public = lib.hasSuffix ".pub";

  # sets up $keys (tmpfs) and $work (under $PWD, images are too big for tmpfs)
  decrypt = vars: ''
    keys=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}")
    work=$(mktemp -d -p "$PWD")
    trap 'rm -rf "$keys" "$work"' EXIT

    umask 077
    ${lib.concatMapStrings (
      n:
      if public n then
        ''
          cp ${vars}/${n} "${local n}"
          chmod 644 "${local n}"
        ''
      else
        ''
          sops decrypt --input-type binary --output-type binary ${vars}/${n} > "${local n}"
        ''
    ) (lib.attrNames (present vars))}
  '';
in
{
  disko =
    {
      name,
      nixos,
      vars,
    }:
    pkgs.writeShellApplication {
      name = "${name}-image";
      runtimeInputs = with pkgs; [
        sops
        qemu-utils
      ];
      text = ''
        out=$PWD/${name}.qcow2
        ${decrypt vars}

        # disko copies without -p, so modes get masked again
        umask 022
        (cd "$work" && ${nixos.config.system.build.diskoImagesScript} ${
          lib.concatStringsSep " " (
            lib.mapAttrsToList (n: dst: "--post-format-files \"${local n}\" ${dst}") (present vars)
          )
        } "$@")

        umask 077
        qemu-img convert -p -c -O qcow2 -o compression_type=zstd "$work/main.raw" "$out"
        echo "$out"
      '';
    };

  sd =
    {
      name,
      nixos,
      vars,
    }:
    let
      files = present vars;
      dirs = lib.unique (map dirOf (lib.attrValues files));
      parents = d: if d == "/" then [ ] else parents (dirOf d) ++ [ d ];
      commands = lib.concatStringsSep "\n" (
        # mkdir fails on dirs that exist, debugfs -f just goes on
        map (d: "mkdir ${d}") (lib.unique (lib.concatMap parents dirs))
        ++ lib.optional (lib.elem "/var/lib/tailscale" dirs) "sif /var/lib/tailscale mode 040700"
        ++ lib.concatLists (
          lib.mapAttrsToList (n: dst: [
            "write ${local n} ${dst}"
            "sif ${dst} mode ${if public n then "0100644" else "0100600"}"
            "sif ${dst} uid 0"
            "sif ${dst} gid 0"
          ]) files
        )
      );
    in
    pkgs.writeShellApplication {
      name = "${name}-image";
      runtimeInputs = with pkgs; [
        sops
        e2fsprogs
        util-linux
        jq
      ];
      text = ''
        out=$PWD/${name}.img
        ${decrypt vars}

        img=$work/${name}.img
        cp --no-preserve=mode ${nixos.config.system.build.sdImage}/sd-image/*.img "$img"

        # the root partition is the sd image's last (and largest) one
        read -r start size < <(sfdisk -J "$img" | jq -r '.partitiontable.partitions | max_by(.size) | "\(.start) \(.size)"')
        dd if="$img" of="$work/root" bs=512 skip="$start" count="$size" conv=sparse status=none
        debugfs -w -f - "$work/root" > /dev/null <<EOF
        ${commands}
        EOF
        dd if="$work/root" of="$img" bs=512 seek="$start" conv=notrunc,sparse status=none

        mv "$img" "$out"
        echo "$out"
      '';
    };
}
