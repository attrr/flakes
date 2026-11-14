{
  pkgs,
  pkgsUnstable,
  ...
}:
{
  programs.vscode = {
    enable = true;
    # 26.05's 1.144 still removes rg from the pre-1.122 path
    package = pkgsUnstable.vscode;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      enkia.tokyo-night
      ms-python.python
      ms-python.black-formatter
      ms-pyright.pyright
      redhat.vscode-yaml
      golang.go
      mkhl.direnv
    ];
    profiles.default = {
      userSettings = {
        # update
        "update.mode" = "none";
        "extensions.autoUpdate" = "off";
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

  allowUnfree.packages =
    (with pkgsUnstable; [
      claude-code
      antigravity-cli
      antigravity-hub
      antigravity-acp
      android-studio
      vscode
    ])
    ++ (with pkgs; [
      vscode-extensions.ms-python.vscode-pylance
    ]);
}
