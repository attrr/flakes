{
  pkgs,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./pi.nix
    ./rea.nix
    ./skills.nix
  ];

  home.sessionVariables = {
    AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.google-chrome}/bin/google-chrome-stable";
  };

  agents.skills.agent-browser = "${pkgsUnstable.agent-browser}/skill-data/core";

  home.packages = with pkgsUnstable; [
    codex
    claude-code
    opencode
    opencode-desktop
    antigravity-cli
    antigravity-hub
    antigravity-acp
    agent-browser
  ];

  allowUnfree.packages = with pkgsUnstable; [
    claude-code
    antigravity-cli
    antigravity-hub
    antigravity-acp
  ];
}
