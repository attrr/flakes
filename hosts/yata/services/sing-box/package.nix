{
  pkgs,
  ...
}:
{
  # v1.14.0-alpha.39 adds direct L3 forwarding from a WireGuard endpoint
  # back to an endpoint, avoiding the failing TUN L3-to-L4 translation path.
  services.sing-box.package = pkgs.sing-box.overrideAttrs (
    finalAttrs: _previousAttrs: {
      version = "1.14.0-alpha.39";
      src = pkgs.fetchFromGitHub {
        owner = "SagerNet";
        repo = "sing-box";
        tag = "v${finalAttrs.version}";
        hash = "sha256-W7YNI20Bc71tvLUfH9Ovzkp8do8xVn2U5Yt/bWuFQh8=";
      };
      vendorHash = "sha256-7ZXgL1mL1Nv7YOlTsmrqZB4ZaoRTpAxO1N0hCBeYaqI=";
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
