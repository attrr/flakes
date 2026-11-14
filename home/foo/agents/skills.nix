{
  lib,
  config,
  ...
}:
let
  skillTargets = [
    ".pi/agent/skills"
    ".agents/skills"
    ".claude/skills"
  ];

  localDir = ./skills;
  localSkills =
    if builtins.pathExists localDir then
      lib.mapAttrs (name: _: localDir + "/${name}") (
        lib.filterAttrs (_: type: type == "directory") (builtins.readDir localDir)
      )
    else
      { };
in
{
  options.agents = {
    skills = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Agent skills linked into every harness skills directory.";
    };

    mcpServers = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = "MCP servers registered into pi's ~/.pi/agent/mcp.json.";
    };
  };

  config = {
    agents.skills = localSkills;

    home.file =
      (lib.concatMapAttrs (
        name: src: lib.genAttrs (map (dir: "${dir}/${name}") skillTargets) (_: { source = src; })
      ) config.agents.skills)
      // lib.optionalAttrs (config.agents.mcpServers != { }) {
        ".pi/agent/mcp.json".text = builtins.toJSON {
          mcpServers = config.agents.mcpServers;
        };
      };
  };
}
