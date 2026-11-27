{
  module = {
    os =
      { lib, pkgs, ... }:
      {
        programs.htop.enable = lib.mkDefault true;
        environment.variables.EDITOR = "mg";
        environment.systemPackages = map lib.getBin (
          with pkgs;
          [
            mg
            curlMinimal
            jq
            mtr
          ]
        );
      };

    nixos =
      {
        config,
        lib,
        pkgs,
        ...
      }:
      {
        imports = [
          ./mitigations.nix
        ];

        config = lib.mkMerge [
          {
            programs.nano.enable = lib.mkDefault false;

            networking.nftables = {
              enable = lib.mkDefault true;
              tables.scanner-blocklist = {
                family = "inet";
                content = ''
                  include "${pkgs.scanner-blocklist-nft}"
                '';
              };
            };
          }

          (lib.mkIf (!config.boot.isContainer) {
            # fixes land in mainline first
            boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

            boot.kernel.sysctl = {
              # io_uring keeps turning up in privilege escalation chains
              "kernel.io_uring_disabled" = lib.mkDefault 2;

              # kernel addresses help exploits; nixos defaults kptr_restrict to 1
              "kernel.kptr_restrict" = lib.mkOverride 999 2;
              "kernel.dmesg_restrict" = lib.mkDefault 1;
              "net.core.bpf_jit_harden" = lib.mkDefault 2;

              # network
              "net.core.default_qdisc" = lib.mkDefault "cake";
              "net.ipv4.tcp_congestion_control" = "bbr";
              "net.ipv4.tcp_slow_start_after_idle" = 0;
              "net.ipv4.tcp_mtu_probing" = 1;
            };
          })

          (lib.mkIf config.nix.enable {
            nix.settings = {
              extra-experimental-features = [
                "nix-command"
                "flakes"
              ];
              allowed-users = [ "@users" ];
              trusted-users = [ "@wheel" ];
            };

            programs.git = {
              enable = lib.mkDefault true;
              package = lib.mkDefault pkgs.gitMinimal;
              config.init.defaultBranch = "main";
            };
          })
        ];
      };
  };

  ctx.os =
    { lib, ctx, ... }:
    {
      networking.hostName = lib.mkDefault ctx.metadata.hostname;
      nixpkgs.hostPlatform = lib.mkDefault ctx.metadata.arch;
    };
}
