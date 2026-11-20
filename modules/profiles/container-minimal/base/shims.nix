# Option shims so we can import Finix's `system/activation` and `networking`
# without importing `modules/finit` (the C binary), `modules/boot`, or `modules/security/wrappers`.
{
  config,
  lib,
  ...
}:
{
  options = {
    boot = {
      # Read by `bootstrap/default.nix` (`cfg.config.boot.isContainer`)
      isContainer = lib.mkOption {
        type = lib.types.bool;
        default = true;
        internal = true;
      };
      # Read by `finix/modules/system/activation/default.nix`
      kernel.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
      };
      initrd.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
      };
      bootspec.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
      };
      # Written by `finix/modules/networking/default.nix`
      kernel.sysctl = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        internal = true;
      };
      initrd.contents = lib.mkOption {
        type = lib.types.listOf lib.types.anything;
        default = [ ];
        internal = true;
      };
    };

    # Written by `finix/modules/security/wrappers/default.nix` (`fileSystems."/run/wrappers"`)
    fileSystems = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      internal = true;
    };

    # Read by `finix/modules/services/openssh/default.nix` and `finix/modules/programs/shadow/default.nix`
    services = {
      sessiond.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
      };
      elogind.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
      };
      seatd.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        internal = true;
      };
    };

    # Read by `finix/modules/system/activation/default.nix` (`switch-to-configuration` substitution)
    finit.package = lib.mkOption {
      type = lib.types.package;
      default = config.programs.coreutils.package;
      internal = true;
    };

    # Finix `modules/networking` omits `nameservers`; declared here for `infra.network`.
    networking.nameservers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
  };
}
