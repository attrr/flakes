{
  lib,
  ctx,
  pkgs,
  ...
}:
let
  wg = ctx.services.wireguard;
  hub = builtins.head wg.peers;
in
{
  imports = [
    ../../hardware/kled.nix
    ../../modules/purpose/ssh.nix
    ../../modules/host/desktop.nix
    ./hardware.nix
    ./disko.nix
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "neko";

  # Configure network connections interactively with nmcli or nmtui.
  networking.networkmanager.enable = true;
  networking.nameservers = map (addr: builtins.head (lib.splitString "/" addr)) hub.addresses;
  networking.wireguard.interfaces = {
    wg0 = {
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

  services.openssh = {
    enable = true;
    ports = ctx.ssh.ports;
    users.foo.authorizedKeys = ctx.ssh.auth-keys;
    lockRootLogin = true;
  };

  users.users.foo = {
    hashedPassword = ctx.ssh.hashed-password;
    shell = pkgs.zsh;
  };

  # Set your time zone.
  time.timeZone = "UTC";

  # Select internationalisation properties.
  # i18n.defaultLocale = "en_US.UTF-8";
  # console = {
  #   font = "Lat2-Terminus16";
  #   keyMap = "us";
  #   useXkbConfig = true; # use xkb.options in tty.
  # };

  # fonts for cjk display
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
    noto-fonts-color-emoji
    liberation_ttf
    dejavu_fonts
    font-awesome
  ];

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Enable CUPS to print documents.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "hplip"
      "iscan"
      "iscan-ds"
      "iscan-data"
      "iscan-v330-bundle"
      "iscan-gt"
      "iscan-gt-f720-bundle"
      "iscan-nt-bundle"
      "iscan-gt-s600-bundle"
      "iscan-gt-s650-bundle"
      "iscan-gt-s80-bundle"
      "iscan-gt-x820-bundle"
      "iscan-gt-x750-bundle"
      "iscan-gt-x770-bundle"
      "iscan-v370-bundle"
      "iscan-perfection-v550-bundle"
    ];
  services.printing = {
    # run on first setup: sudo hp-setup -i -a
    enable = true;
    drivers = [ pkgs.hplipWithPlugin ];
  };
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.epkowa ];
  };
  users.users.foo.extraGroups = [
    "lp"
    "scanner"
  ];

  # Define a user account. Don't forget to set a password with ‘passwd’.
  programs.ssh.enableAskPassword = false;
  security.sudo.wheelNeedsPassword = false;
  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  programs.firefox.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  # networking.firewall.enable = false;

  system.stateVersion = "25.11";

}
