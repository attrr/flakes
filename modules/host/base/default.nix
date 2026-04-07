{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./override.nix
  ];

  nix.settings = {
    extra-experimental-features = [
      "nix-command"
      "flakes"
    ];
    trusted-users = [ "@wheel" ];
  };
  security.sudo.wheelNeedsPassword = false;

  # basic sysctl
  boot.kernel.sysctl = {
    "net.core.default_qdisc" = lib.mkDefault "cake";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.ipv4.tcp_slow_start_after_idle" = 0;
    "net.ipv4.tcp_mtu_probing" = 1;
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

  # basic maintenance tools
  environment.systemPackages = with pkgs; [
    curl
    tmux
    jq
    mtr
    wget
    nftables
    dig
    # tui
    iotop
    htop
    iftop
  ];
}
