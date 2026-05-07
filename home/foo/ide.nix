{
  pkgs,
  config,
  pkgsUnstable,
  ...
}:
{
  programs.vscode = {
    enable = true;
    package = pkgs.vscodium;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      enkia.tokyo-night
      ms-python.python
      ms-python.black-formatter
      ms-pyright.pyright
      redhat.vscode-yaml
      golang.go
      Google.gemini-cli-vscode-ide-companion
      mkhl.direnv
    ];
    profiles.default = {
      userSettings = {
        # update
        "update.mode" = "none";
        "extensions.autoUpdate" = false;
        # theme
        "workbench.colorTheme" = "Tokyo Night Light";
        # pranthese
        "editor.bracketPairColorization.enabled" = true;
        "editor.guides.bracketPairs" = "active";
        # nix
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "nix.formatterPath" = "nixfmt";
        # python
        "python.analysis.typeCheckingMode" = "standard";
        "redhat.telemetry.enabled" = false;
      };
    };
  };

  home.packages =
    (with pkgsUnstable; [
      gemini-cli
      opencode
      opencode-desktop
    ])
    ++ (with pkgs; [
      nixfmt
      nixd
      prettier
      black
    ]);

  home.file.".antigravity/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.vscode-oss/extensions";

  xdg.configFile."Antigravity/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/VSCodium/User/settings.json";

  allowUnfree.packages = with pkgs; [
    antigravity
    vscode
    vscode-extensions.ms-python.vscode-pylance
  ];
}
