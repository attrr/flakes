{
  includes = [ ../base ];

  module.nixos =
    {
      config,
      lib,
      modulesPath,
      pkgs,
      ...
    }:
    let
      cfg = config.infra.server;
    in
    {
      imports = [
        (modulesPath + "/profiles/minimal.nix")
        (modulesPath + "/profiles/headless.nix")
      ];

      options.infra.server.lowend = lib.mkEnableOption "low-memory server tuning";
      config = lib.mkMerge [
        {
          services.journald.extraConfig = lib.mkDefault ''
            Storage=persistent
            SystemMaxUse=100M
            SystemMaxFileSize=10M
            MaxRetentionSec=2week
          '';
          zramSwap = {
            enable = lib.mkDefault true;
            algorithm = "zstd";
          };

          system.disableInstallerTools = lib.mkDefault true;
          fonts.fontconfig.enable = lib.mkDefault false;
          i18n.supportedLocales = lib.mkDefault [
            "C.UTF-8/UTF-8"
            "en_US.UTF-8/UTF-8"
          ];

          nixpkgs.flake = {
            setFlakeRegistry = lib.mkDefault false;
            setNixPath = lib.mkDefault false;
          };
          nix.gc = {
            automatic = lib.mkDefault true;
            dates = lib.mkDefault "weekly";
            options = lib.mkDefault "--delete-older-than 14d";
            persistent = lib.mkDefault true;
            randomizedDelaySec = lib.mkDefault "1h";
          };
          nix.settings = {
            auto-optimise-store = lib.mkDefault true;
            min-free = lib.mkDefault (512 * 1024 * 1024);
            max-free = lib.mkDefault (1024 * 1024 * 1024);
          };

          environment.systemPackages = with pkgs; [
            tmux
            dig
            nethogs
            iftop
          ];
        }
        (lib.mkIf cfg.lowend {
          zramSwap.memoryPercent = lib.mkDefault 100;
          services.tailscale.lowMemory = lib.mkDefault true;
        })
      ];
    };

  ctx = {
    os =
      { ctx, lib, ... }:
      {
        services.openssh = {
          enable = lib.mkDefault true;
          ports = lib.mkDefault ctx.ssh.ports;
          users.sysadm.authorizedKeys = lib.mkDefault ctx.ssh.auth-keys;
          lockRootLogin = lib.mkDefault true;
        };

        # wheel means ssh-key-only admin accounts (deploy-rs sudoes through
        # them), services never are
        security.sudo.wheelNeedsPassword = false;
      };

    nixos =
      { ctx, lib, ... }:
      {
        infra.server.lowend = lib.mkIf (
          ctx.metadata.specs.memory != null && ctx.metadata.specs.memory <= 1024
        ) (lib.mkDefault true);
      };
  };
}
