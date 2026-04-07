{
  pkgs,
  config,
  pkgsUnstable,
  ...
}:
let
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
    extraPackages =
      epkgs:
      [
        # default
        epkgs.rainbow-delimiters
        # basic mode
        epkgs.yaml-mode
        # ui
        epkgs.doom-themes
        epkgs.doom-modeline
        epkgs.nerd-icons
        # tools
        epkgs.magit
        epkgs.colorful-mode
        epkgs.indent-bars
        epkgs.vterm
        epkgs.eat
        epkgs.multi-vterm
        # comeplete
        epkgs.corfu
        epkgs.corfu-terminal
        epkgs.kind-icon
        epkgs.orderless
        epkgs.vertico
        epkgs.marginalia
        epkgs.consult
        epkgs.yasnippet
        # org
        epkgs.org-bullets
        # lsp
        epkgs.eglot
        epkgs.consult-eglot
        epkgs.apheleia
        epkgs.eca
        pkgsUnstable.emacsPackages.agent-shell
        # mode
        epkgs.systemd
        epkgs.nix-mode
        epkgs.go-mode
        epkgs.python
      ];
  };

  services.emacs = {
    enable = true;
    package = config.programs.emacs.finalPackage;
    defaultEditor = true;
  };

  home.packages = with pkgs; [
    # shell
    bash-language-server
    shfmt
    # nix
    nil
    nixd
    nixfmt
    # json
    vscode-langservers-extracted
    prettier
    # systemd
    systemd-lsp
    # golang
    go
    gopls
    # python
    python3
    black
    pyright
  ];

  xdg.desktopEntries = {
    emacs-vterm = {
      name = "Emacs VTerm";
      genericName = "Terminal";
      comment = "Run Emacs vterm as a standalone terminal";
      # -a "" to ensure it hits the daemon
      exec = "${config.programs.emacs.finalPackage}/bin/emacsclient -c -a \"\" --eval \"(multi-vterm)\"";
      icon = "utilities-terminal";
      terminal = false;
      categories = [
        "System"
        "TerminalEmulator"
      ];
      settings = {
        StartupWMClass = "Emacs";
      };
    };
  };
}
