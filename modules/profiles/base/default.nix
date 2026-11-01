# The everyday bits; network tuning, security posture and bug workarounds in
# their own files.
{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./network.nix
    ./hardening.nix
    ./mitigations.nix
    ./caddy.nix
  ];

  nix.settings = {
    extra-experimental-features = [
      "nix-command"
      "flakes"
    ];
    allowed-users = [ "@users" ];
    trusted-users = [ "@wheel" ];
  };

  # enable zram regardless
  zramSwap.enable = lib.mkDefault true;
  zramSwap.algorithm = "zstd";

  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  programs.git = {
    enable = true;
    package = lib.mkDefault pkgs.gitMinimal;
    config = {
      init.defaultBranch = "main";
    };
  };

  programs.htop = {
    enable = true;
    settings = rec {
      highlight_base_name = true;
      tree_view = true;
      show_cpu_frequency = true;
      # less verbose
      show_program_path = false;
      hide_kernel_threads = true;
      hide_userland_threads = true;
      # steal time
      detailed_cpu_time = true;

      left_meters = [
        "AllCPUs"
        "Memory"
        "Swap"
      ];
      left_meter_modes = (lib.replicate (builtins.length left_meters) 1);

      right_meters = [
        "NetworkIO"
        "DiskIO"
        "Tasks"
        "LoadAverage"
        "Uptime"
        "CPU"
      ];
      right_meter_modes = (lib.replicate (builtins.length left_meters) 2);
    };
  };

  # basic maintenance tools
  environment.systemPackages = with pkgs; [
    curl
    tmux
    jq
    mtr
    wget
    nftables
    dig
    nethogs
    iftop
  ];
}
