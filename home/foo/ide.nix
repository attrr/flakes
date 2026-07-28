{
  pkgs,
  config,
  pkgsUnstable,
  ...
}:
{
  programs.vscode = {
    enable = true;
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
      anthropic.claude-code
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
        "claudeCode.preferredLocation" = "panel";
      };
    };
  };

  home.packages =
    (with pkgsUnstable; [
      gemini-cli
      codex
      claude-code
      opencode
      opencode-desktop
    ])
    ++ (with pkgs; [
      antigravity-hub
      antigravity-ide
      nixfmt
      nixd
      prettier
      black
    ]);

  home.file.".antigravity-ide/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.vscode/extensions";

  xdg.configFile."Antigravity IDE/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/Code/User/settings.json";

  allowUnfree.packages = with pkgs; [
    claude-code
    antigravity-hub
    antigravity-ide
    vscode
    vscode-extensions.ms-python.vscode-pylance
    vscode-extensions.anthropic.claude-code
  ];
}
