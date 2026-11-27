# Temporary kernel CVE workarounds. Blocks listed modules on unpatched kernels
# and emits a warning once the running kernel includes the fix.
#
#   dirty-frag = {
#     ref = "CVE-2026-43284, CVE-2026-43500";
#     modules = [ "esp4" "esp6" "rxrpc" ];
#     fixedIn = [ "6.12.87" "6.18.28" "7.0.5" "7.1" ];
#   };
{ config, lib, ... }:
let
  mitigations = { };

  kernel = config.boot.kernelPackages.kernel.version;
  isFixed =
    fixedIn:
    let
      latest = lib.last (lib.sort lib.versionOlder fixedIn);
      sameBranch = v: lib.versions.majorMinor v == lib.versions.majorMinor kernel;
    in
    lib.versionAtLeast kernel latest
    || lib.any (v: sameBranch v && lib.versionAtLeast kernel v) fixedIn;

  entries = lib.mapAttrsToList (name: m: m // { inherit name; }) mitigations;
  partitioned = lib.partition (m: isFixed m.fixedIn) entries;
  active = partitioned.wrong;
  obsolete = partitioned.right;
  blockedModules = lib.concatMap (m: m.modules) active;
in
{
  config = lib.mkIf (!config.boot.isContainer && mitigations != { }) {
    boot.blacklistedKernelModules = blockedModules;
    # blacklist only blocks autoloading; `install ... false` also blocks explicit modprobe
    boot.extraModprobeConfig = lib.concatMapStringsSep "\n" (
      mod: "install ${mod} /run/current-system/sw/bin/false"
    ) blockedModules;

    warnings = map (
      m:
      "mitigation ${m.name} (${m.ref}): kernel ${kernel} has the fix, drop it from profiles/base/mitigations.nix"
    ) obsolete;
  };
}
