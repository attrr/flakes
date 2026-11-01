# Workarounds for specific kernel bugs, until the kernel has the fix. An entry
# keeps its modules from loading on kernels without the fix, and warns on ones
# with it: then it should go. fixedIn lists the first fixed release per stable
# branch, as the CVE record does; a kernel past all of them counts as fixed.
#
#   dirty-frag = {
#     ref = "CVE-2026-43284, CVE-2026-43500";
#     modules = [ "esp4" "esp6" "rxrpc" ];
#     fixedIn = [ "6.12.87" "6.18.28" "7.0.5" "7.1" ];
#   };
#
# Past ones (all fixed by 7.1): Copy Fail (algif_aead), Dirty Frag (esp4, esp6,
# rxrpc), PinTheft (rds), Fragnesia (esp4, esp6).
{ lib, config, ... }:
let
  mitigations = { };

  kernel = config.boot.kernelPackages.kernel.version;
  fixed =
    fixedIn:
    lib.versionAtLeast kernel (lib.last (lib.sort lib.versionOlder fixedIn))
    || lib.any (
      v: lib.versions.majorMinor v == lib.versions.majorMinor kernel && lib.versionAtLeast kernel v
    ) fixedIn;
  parts = lib.partition (m: fixed m.fixedIn) (
    lib.mapAttrsToList (name: m: m // { inherit name; }) mitigations
  );
  modules = lib.concatMap (m: m.modules) parts.wrong;
in
{
  boot.blacklistedKernelModules = modules;
  # the blacklist only stops autoloading, this stops modprobe too
  boot.extraModprobeConfig = lib.concatMapStringsSep "\n" (
    mod: "install ${mod} /run/current-system/sw/bin/false"
  ) modules;

  warnings = map (
    m:
    "mitigation ${m.name} (${m.ref}): kernel ${kernel} has the fix, drop it from profiles/base/mitigations.nix"
  ) parts.right;
}
