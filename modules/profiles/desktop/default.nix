{
  module.nixos =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      cfg = config.infra.desktop;
    in
    {
      imports = [
        ../base
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
    };

  ctx.nixos =
    {
      lib,
      config,
      ctx,
      ...
    }:
    let
      wg = ctx.services.wireguard;
      hub = builtins.head wg.peers;
    in
    {
      networking.hostName = ctx.metadata.hostname;

      assertions = [
        {
          assertion = config.users.users.foo.hashedPassword != null;
          message = "${ctx.metadata.hostname}: set ssh.hashed-password in ctx";
        }
      ];
      users.users.foo.hashedPassword = ctx.ssh.hashed-password;

      services.openssh = {
        enable = true;
        ports = ctx.ssh.ports;
        users.foo.authorizedKeys = ctx.ssh.auth-keys;
        lockRootLogin = true;
      };

      networking.nameservers = map (addr: builtins.head (lib.splitString "/" addr)) hub.addresses;
      networking.wireguard.interfaces.wg0 = {
        ips = wg.addresses;
        listenPort = 51820;
        privateKeyFile = wg.private-key.path;
        peers = [
          {
            publicKey = hub.public-key;
            presharedKeyFile = wg.pre-shared-key.path;
            allowedIPs = [
              "0.0.0.0/0"
              "::/0"
            ];
            endpoint = hub.endpoint;
          }
        ];
      };
    };
}
