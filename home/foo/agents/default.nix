{
  pkgs,
  pkgsUnstable,
  ...
}:
{
  imports = [
    ./pi.nix
    ./skills.nix
  ];

  agents.tools.agent-browser = {
    package = pkgsUnstable.agent-browser;
    env.AGENT_BROWSER_EXECUTABLE_PATH = "${pkgs.google-chrome}/bin/google-chrome-stable";
    skills.agent-browser = {
      source = "skill-data/core";
      targets = [
        "pi"
        "opencode"
      ];
    };
  };

  agents.tools.rea = {
    package = pkgs.rea.override { ghidra = pkgsUnstable.ghidra; };
    skills.reverse-engineer-anything = "lib/node_modules/rea-agents/skills/reverse-engineer-anything";
    mcp.rea.args = [ "mcp" ];
  };

  programs.opencode.enable = true;

  programs.codex = {
    enable = true;
    package = pkgsUnstable.codex;
  };

  programs.claude-code = {
    enable = true;
    package = pkgsUnstable.claude-code;
    enableMcpIntegration = true;
  };

  programs.antigravity-cli = {
    enable = true;
    package = pkgsUnstable.antigravity-cli;
    enableMcpIntegration = true;
  };

  home.packages = with pkgsUnstable; [
    antigravity-hub
    antigravity-acp
  ];

  nixpkgs.allowUnfree.packages = with pkgsUnstable; [
    claude-code
    antigravity-cli
    antigravity-hub
    antigravity-acp
  ];
}
