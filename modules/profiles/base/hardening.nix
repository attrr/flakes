# Standing security posture. Workarounds for specific bugs go in ./mitigations.nix.
{
  lib,
  pkgs,
  config,
  ...
}:
let
  mysql = config.services.mysql;
  mysqlGid = config.users.groups.${mysql.group}.gid or null;
in
{
  # fixes land in mainline first, stable branches get them later (or never)
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  boot.kernel.sysctl = {
    # io_uring keeps turning up in privilege escalation chains (PinTheft) and
    # nothing here needs it, except mariadb: it gets it through its group
    "kernel.io_uring_disabled" = lib.mkDefault (if mysql.enable then 1 else 2);
    "kernel.io_uring_group" = lib.mkIf (mysql.enable && mysqlGid != null) mysqlGid;
    # kernel addresses help exploits; nixos defaults kptr_restrict to 1
    "kernel.kptr_restrict" = lib.mkOverride 999 2;
    "kernel.dmesg_restrict" = lib.mkDefault 1;
    "net.core.bpf_jit_harden" = lib.mkDefault 2;
  };

  # wheel means ssh-key-only admin accounts, services never are
  security.sudo.wheelNeedsPassword = false;
}
