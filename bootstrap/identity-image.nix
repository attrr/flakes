# A script that builds a nixos config's disko image as an existing host: its
# ssh host key (= sops age key) and tailscale node, kept sops-encrypted (admin
# only) in <identity>/, are decrypted to tmpfs and copied into the image.
# Writes ./<name>.qcow2 (zstd compressed, mode 600: it holds private keys).
{ lib, pkgs }:
{
  name,
  nixos,
  identity,
}:
let
  targets = {
    "ssh_host_ed25519_key" = "/etc/ssh/ssh_host_ed25519_key";
    "ssh_host_ed25519_key.pub" = "/etc/ssh/ssh_host_ed25519_key.pub";
    "tailscaled.state" = "/var/lib/tailscale/tailscaled.state";
  };
  files = lib.filterAttrs (n: _: builtins.pathExists "${identity}/${n}") targets;
in
pkgs.writeShellApplication {
  name = "${name}-image";
  runtimeInputs = with pkgs; [
    sops
    qemu-utils
  ];
  text = ''
    out=$PWD/${name}.qcow2
    keys=$(mktemp -d -p "''${XDG_RUNTIME_DIR:-/tmp}")
    # the raw image is ~10G sparse, too big for tmpfs
    work=$(mktemp -d -p "$PWD")
    trap 'rm -rf "$keys" "$work"' EXIT

    umask 077
    ${lib.concatMapStrings (n: ''
      sops decrypt --input-type binary --output-type binary ${identity}/${n} > "$keys/${n}"
      ${lib.optionalString (lib.hasSuffix ".pub" n) ''chmod 644 "$keys/${n}"''}
    '') (lib.attrNames files)}

    # disko copies without -p, so modes get masked again
    umask 022
    (cd "$work" && ${nixos.config.system.build.diskoImagesScript} ${
      lib.concatStringsSep " " (
        lib.mapAttrsToList (n: dst: "--post-format-files \"$keys/${n}\" ${dst}") files
      )
    } "$@")

    umask 077
    qemu-img convert -p -c -O qcow2 -o compression_type=zstd "$work/main.raw" "$out"
    echo "$out"
  '';
}
