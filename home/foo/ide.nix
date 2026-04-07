{ pkgs, pkgsUnstable, ... }:
{
  programs.vscode = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      enkia.tokyo-night
      ms-python.python
      ms-python.vscode-pylance
      ms-python.black-formatter
      ms-pyright.pyright
      redhat.vscode-yaml
      golang.go
      Google.gemini-cli-vscode-ide-companion
    ];
    profiles.default = {
      userSettings = {
        "workbench.colorTheme" = "Tokyo Night Light";
        # nix
        "nix.enableLanguageServer" = true;
        "nix.serverPath" = "nixd";
        "nix.formatterPath" = "nixfmt";
        "[nix]" = {
          "editor.bracketPairColorization.enabled" = true;
          "editor.guides.bracketPairs" = "active";
        };
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

  allowUnfree.packages = with pkgs; [
    antigravity
    vscode
    vscode-extensions.ms-python.vscode-pylance
  ];
}
