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
