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
      codex
      claude-code
      opencode
      opencode-desktop
      pi-coding-agent
      antigravity-cli
      antigravity-hub
      antigravity-acp
      # 26.05's is a release behind the flatpak it replaced
      android-studio
    ])
    ++ (with pkgs; [
      nixfmt
      nixd
      prettier
      black
    ]);

  home.file.".antigravity-ide/extensions".source =
    config.lib.file.mkOutOfStoreSymlink "${config.home.homeDirectory}/.vscode/extensions";

  xdg.configFile."Antigravity IDE/User/settings.json".source =
    config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/Code/User/settings.json";

  allowUnfree.packages =
    (with pkgsUnstable; [
      claude-code
      antigravity-cli
      antigravity-hub
      antigravity-acp
      android-studio
    ])
    ++ (with pkgs; [
      vscode
      vscode-extensions.ms-python.vscode-pylance
      vscode-extensions.anthropic.claude-code
    ]);
}
