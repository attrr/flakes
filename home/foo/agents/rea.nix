{
  pkgs,
  pkgsUnstable,
  ...
}:
let
  rea = pkgs.symlinkJoin {
    name = "rea-${pkgs.rea.version}";
    paths = [ pkgs.rea ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      for program in rea rea-agents; do
        rm "$out/bin/$program"
        makeWrapper "${pkgs.rea}/bin/$program" "$out/bin/$program" \
          --set-default GHIDRA_INSTALL_DIR "${pkgsUnstable.ghidra}/lib/ghidra" \
          --set-default REA_JADX_MCP_JAR "${pkgs.jadx-headless-mcp}/share/java/jadx-headless-mcp-all.jar"
      done
    '';
  };
in
{
  home.packages = [ rea ];
  agents.skills.reverse-engineer-anything = "${pkgs.rea}/lib/node_modules/rea-agents/skills/reverse-engineer-anything";
  agents.mcpServers.rea = {
    command = "${rea}/bin/rea";
    args = [ "mcp" ];
  };
}
