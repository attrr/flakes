# Container-only option shims so we can import finix's `finit`, `system/activation`,
# `security`, and `networking` without importing `modules/boot` or `modules/finit/{initrd,mount}.nix`.
{ lib, ... }:
let
  mkShim =
    type: default:
    lib.mkOption {
      inherit type default;
      internal = true;
    };
  mkDisabled = mkShim lib.types.anything { enable = false; };
  mkAttrs = mkShim (lib.types.attrsOf lib.types.anything) { };
  mkList = mkShim (lib.types.listOf lib.types.anything) [ ];
in
{
  options = {
    boot = {
      # Read by `bootstrap/default.nix` (`cfg.config.boot.isContainer`)
      isContainer = mkShim lib.types.bool true;
      # Read by `finix/modules/system/activation/default.nix`
      init = lib.mkOption {
        type = lib.types.path;
        internal = true;
      };
      kernel = {
        enable = mkShim lib.types.bool false;
        sysctl = mkAttrs;
      };
      initrd = {
        enable = mkShim lib.types.bool false;
        contents = mkList;
      };
      bootspec = mkDisabled;
      supportedFilesystems = mkAttrs;
    };

    # Written by `finix/modules/security/wrappers/default.nix` (`fileSystems."/run/wrappers"`)
    fileSystems = mkAttrs;

    # Read by `openssh`, `shadow`, `sysklogd`, and `finit/options.nix`
    services = lib.genAttrs [
      "sessiond"
      "elogind"
      "seatd"
      "keventd"
      "gardendevd"
      "udev"
      "mdevd"
    ] (_: mkDisabled);

    # Read by `finix/modules/finit/options.nix`
    programs.plymouth = mkShim lib.types.anything {
      enable = false;
      package = null;
    };
  };
}
