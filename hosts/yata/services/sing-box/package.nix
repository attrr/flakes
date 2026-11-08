{
  pkgs,
  ...
}:
{
  # 1.14 ahead of nixpkgs; once it has that, only the patch stays
  services.sing-box.package = pkgs.sing-box.overrideAttrs (
    finalAttrs: _previousAttrs: {
      version = "1.14.4";
      src = pkgs.fetchFromGitHub {
        owner = "SagerNet";
        repo = "sing-box";
        tag = "v${finalAttrs.version}";
        hash = "sha256-1tP0gXUTLGVR32c11nypsZSx2FtBOmKMTJkt+7j/fJU=";
      };
      vendorHash = "sha256-xZWWzvyTrbaxqHG1UdKOVLOd5dPf9z6JfPJf3WeTm5Y=";
      # system WireGuard unconditionally enables TUN GSO upstream.  yata's TUN
      # driver rejects those vnet-hdr writes with EINVAL, which breaks peer
      # forwarding.  Keep system mode (needed for LAN access), but use normal
      # MTU-sized packets instead.
      postPatch = (_previousAttrs.postPatch or "") + ''
        substituteInPlace transport/wireguard/device_system.go \
          --replace-fail 'GSO:            true,' 'GSO:            false,'
      '';
    }
  );
}
