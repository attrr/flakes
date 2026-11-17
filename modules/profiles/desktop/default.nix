{
  lib,
  pkgs,
  self,
  config,
  ...
}:
let
  cfg = config.infra.desktop;
in
{
  imports = [
    "${self}/modules/profiles/base"
    ./boot.nix
    ./i18n.nix
    ./gnome.nix
    ./printing.nix
  ];

  options.infra.desktop = {
    primaryUser = lib.mkOption {
      type = lib.types.str;
      default = "foo";
    };

    enableLibvirtd = lib.mkEnableOption "";
  };

  config = lib.mkMerge [
    {
      time.timeZone = "UTC";
      networking.networkmanager.enable = true;

      programs.zsh.enable = true;
      programs.git.package = pkgs.git;
      programs.firefox.enable = true;

      users.groups."${cfg.primaryUser}".gid = 1000;
      users.users."${cfg.primaryUser}" = {
        uid = 1000;
        group = "${cfg.primaryUser}";
        shell = pkgs.zsh;

        extraGroups = [
          "users"
          "wheel"
          "dialout" # serial
        ]
        ++ lib.optional config.security.tpm2.enable "tss";
      };

      # for system-wide polkit rules
      environment.systemPackages = [ pkgs.keepassxc ];
    }

    (lib.mkIf cfg.enableLibvirtd {
      virtualisation.libvirtd = {
        enable = true;
        qemu.swtpm.enable = lib.mkDefault true;
      };
      programs.virt-manager.enable = lib.mkDefault true;
      users.users."${cfg.primaryUser}".extraGroups = [ "libvirtd" ];
    })
  ];
}
