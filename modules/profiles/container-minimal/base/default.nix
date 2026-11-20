{
  config,
  finix,
  lib,
  ...
}:
{
  imports = [
    "${finix}/modules/lib"
    "${finix}/modules/misc"
    "${finix}/modules/environment"
    "${finix}/modules/users"
    "${finix}/modules/nixos/ids.nix"
    "${finix}/modules/nixos/ca.nix"
    "${finix}/modules/programs/coreutils"
    "${finix}/modules/programs/sh"
    "${finix}/modules/programs/bash"
    "${finix}/modules/programs/shadow"
    "${finix}/modules/programs/sudo"
    "${finix}/modules/programs/ifupdown-ng"
    "${finix}/modules/services/openssh"
    "${finix}/modules/security"
    "${finix}/modules/time"
    "${finix}/modules/networking"
    "${finix}/modules/providers/bootloader"
    "${finix}/modules/providers/firewall"
    "${finix}/modules/providers/privileges"
    "${finix}/modules/services/nftables"
    "${finix}/modules/system/activation"
    "${finix}/modules/system/activation/specialisation.nix"
    "${finix}/modules/system/activation/switchable-system.nix"
    "${finix}/modules/system/nixos-compat.nix"
    ./shims.nix
    ./init.nix
    ./lustrate.nix
    ./sops.nix
  ];

  config = lib.mkMerge [
    (lib.mkIf config.programs.ifupdown-ng.enable {
      finit.tasks.ifupdown-ng.exec-start-pre = ''
        ${config.programs.coreutils.package}/bin/mkdir -p /run/network
        if [ -e /run/ifstate ] && [ /run/ifstate -ot /proc/1 ]; then
          ${config.programs.coreutils.package}/bin/rm -f /run/ifstate /run/ifstate.*.lock
        fi
      '';
    })

    (lib.mkIf config.services.nftables.enable {
      # Finix's `nixos-firewall-tool` checks `/etc/finit.d/nftables.conf` to detect the nftables backend.
      environment.etc."finit.d/nftables.conf".text = "";
    })
  ];
}
