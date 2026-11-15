{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.agents;

  # Wrap every bin of `package` with default env and extra PATH entries.
  wrapPackage =
    name:
    {
      package,
      env,
      path,
    }:
    if env == { } && path == [ ] then
      package
    else
      pkgs.symlinkJoin {
        name = "${name}-wrapped-${package.version or "0"}";
        paths = [ package ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postBuild = ''
          for bin in "$out"/bin/*; do
            [ -e "$bin" ] || continue
            wrapProgram "$bin" ${
              lib.escapeShellArgs (
                lib.concatLists (
                  lib.mapAttrsToList (k: v: [
                    "--set-default"
                    k
                    (toString v)
                  ]) env
                )
                ++ lib.optionals (path != [ ]) [
                  "--prefix"
                  "PATH"
                  ":"
                  (lib.makeBinPath path)
                ]
              )
            }
          done
        '';
        meta = package.meta or { };
      };

  # Harnesses with a home-manager module get skills via programs.<module>.skills
  # (only applied when that module is enabled); the rest are linked by hand.
  hmTargets = {
    claude = "claude-code";
    opencode = "opencode";
    codex = "codex";
    agy = "antigravity-cli";
  };
  fileTargets = {
    pi = ".pi/agent/skills";
  };

  # `targets = null` links into agents.defaultSkillDirs; otherwise into the
  # listed harnesses' own skill directories.
  targetsOption = mkOption {
    type = types.nullOr (types.listOf (types.enum (lib.attrNames (hmTargets // fileTargets))));
    default = null;
    description = "Target harnesses; null uses agents.defaultSkillDirs.";
  };

  skillType = types.coercedTo types.path (source: { inherit source; }) (
    types.submodule {
      options = {
        source = mkOption {
          type = types.path;
          description = "Skill directory containing SKILL.md.";
        };
        targets = targetsOption;
      };
    }
  );

  toolType = types.submodule (
    { name, config, ... }:
    {
      options = {
        package = mkOption {
          type = types.package;
          description = "CLI package; installed (wrapped with env/path) into home.packages.";
        };

        env = mkOption {
          type = types.attrsOf (types.either types.str types.path);
          default = { };
          description = "Default environment variables (--set-default) for the package's binaries.";
        };

        path = mkOption {
          type = types.listOf types.package;
          default = [ ];
          description = "Packages prepended to PATH for the package's binaries.";
        };

        skills = mkOption {
          type = types.attrsOf (
            types.coercedTo types.str (source: { inherit source; }) (
              types.submodule {
                options = {
                  source = mkOption {
                    type = types.str;
                    description = "Skill directory, relative to `package` (or absolute).";
                  };
                  targets = targetsOption;
                };
              }
            )
          );
          default = { };
          description = "Skills shipped by the package, merged into agents.skills.";
        };

        mcp = mkOption {
          type = types.attrsOf (
            types.submodule {
              freeformType = types.attrsOf types.anything;
              options.command = mkOption {
                type = types.str;
                default = lib.getExe config.finalPackage;
                defaultText = lib.literalExpression "lib.getExe finalPackage";
              };
            }
          );
          default = { };
          description = "MCP servers provided by the package, merged into programs.mcp.servers.";
        };

        finalPackage = mkOption {
          type = types.package;
          readOnly = true;
          default = wrapPackage name { inherit (config) package env path; };
          description = "The wrapped package.";
        };
      };
    }
  );

  localDir = ./skills;
  localSkills = lib.optionalAttrs (builtins.pathExists localDir) (
    lib.mapAttrs (name: _: localDir + "/${name}") (
      lib.filterAttrs (_: type: type == "directory") (builtins.readDir localDir)
    )
  );

  toolSkills = lib.concatMapAttrs (
    _: tool:
    lib.mapAttrs (_: skill: {
      inherit (skill) targets;
      source = if lib.hasPrefix "/" skill.source then skill.source else "${tool.package}/${skill.source}";
    }) tool.skills
  ) cfg.tools;

  skillsFor =
    target:
    lib.mapAttrs (_: skill: skill.source) (
      lib.filterAttrs (_: skill: lib.elem target (lib.toList skill.targets)) cfg.skills
    );

  usedHmTargets = lib.filterAttrs (target: _: skillsFor target != { }) hmTargets;

  # pi has no programs.pi module; render programs.mcp.servers for it ourselves.
  piMcpServers = lib.mapAttrs (
    name: server:
    lib.hm.mcp.transformMcpServer {
      inherit server;
      extraTransforms = [ (lib.hm.mcp.wrapEnvFilesCommand { inherit pkgs name; }) ];
    }
  ) config.programs.mcp.servers;

  # opencode and codex mix MCP with user-writable state in a single file, so we
  # merge MCP entries into the live files on activation instead of symlinking.
  opencodeMcpServers = lib.mapAttrs (
    _: server:
    lib.hm.mcp.transformMcpServer {
      inherit server;
      exclude = [
        "args"
        "env"
      ];
      extraTransforms = [
        (
          s:
          let
            isRemote = s ? url && s.url != null;
            renderedEnv = lib.hm.mcp.renderEnv (p: "{file:${p}}") (s.env or { });
          in
          lib.optionalAttrs (s.enabled or null != null) { inherit (s) enabled; }
          // {
            type = if isRemote then "remote" else "local";
          }
          // (
            if isRemote then
              { inherit (s) url; } // lib.optionalAttrs (s.headers or { } != { }) { inherit (s) headers; }
            else
              {
                command = [ s.command ] ++ (s.args or [ ]);
              }
              // lib.optionalAttrs (renderedEnv != { }) { environment = renderedEnv; }
          )
        )
      ];
    }
  ) config.programs.mcp.servers;

  codexMcpServers = lib.mapAttrs (
    name: server:
    lib.hm.mcp.transformMcpServer {
      inherit server;
      exclude = [
        "headers"
        "type"
      ];
      extraTransforms = [
        (s: s // lib.optionalAttrs (s.headers or { } != { }) { http_headers = s.headers; })
        lib.hm.mcp.addType
        (lib.hm.mcp.wrapEnvFilesCommand { inherit pkgs name; })
      ];
    }
  ) config.programs.mcp.servers;

  codexMcpToml = (pkgs.formats.toml { }).generate "codex-mcp.toml" { mcp_servers = codexMcpServers; };
in
{
  options.agents = {
    defaultSkillDirs = mkOption {
      type = types.listOf types.str;
      default = [
        ".agents/skills" # pi, codex, opencode
        ".claude/skills" # claude
        ".gemini/config/skills" # agy (cli + hub)
      ];
      description = "Shared directories used when a skill omits targets.";
    };

    skills = mkOption {
      type = types.attrsOf skillType;
      default = { };
      description = "Standalone agent skills, as a path or { source; targets; }.";
    };

    tools = mkOption {
      type = types.attrsOf toolType;
      default = { };
      description = "CLI packages for agents, with their optional skills and MCP servers.";
    };
  };

  config = {
    assertions = lib.mapAttrsToList (target: module: {
      assertion = config.programs.${module}.enable;
      message = "agents.skills targets `${target}`, but programs.${module} is not enabled.";
    }) usedHmTargets;

    agents.skills = localSkills // toolSkills;

    home.packages = lib.mapAttrsToList (_: tool: tool.finalPackage) cfg.tools;

    programs =
      lib.mapAttrs' (
        target: module:
        lib.nameValuePair module (lib.mkIf (usedHmTargets ? ${target}) { skills = skillsFor target; })
      ) hmTargets
      // {
        mcp = lib.mkIf (lib.any (tool: tool.mcp != { }) (lib.attrValues cfg.tools)) {
          enable = true;
          servers = lib.concatMapAttrs (_: tool: tool.mcp) cfg.tools;
        };
      };

    home.file =
      # targets = null: shared directories
      lib.concatMapAttrs (
        name: skill:
        lib.optionalAttrs (skill.targets == null) (
          lib.genAttrs (map (dir: "${dir}/${name}") cfg.defaultSkillDirs) (_: {
            inherit (skill) source;
          })
        )
      ) cfg.skills
      # harnesses without a home-manager module
      // lib.concatMapAttrs (
        target: dir:
        lib.mapAttrs' (name: source: lib.nameValuePair "${dir}/${name}" { inherit source; }) (
          skillsFor target
        )
      ) fileTargets
      // lib.optionalAttrs (piMcpServers != { }) {
        ".pi/agent/mcp.json".text = builtins.toJSON { mcpServers = piMcpServers; };
      };

    home.activation = lib.mkIf (config.programs.mcp.servers != { }) {
      mergeAgentMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${lib.optionalString
          (config.programs.opencode.enable && !config.programs.opencode.enableMcpIntegration)
          ''
            opencodeCfg="${config.xdg.configHome}/opencode/opencode.json"
            if [ ! -L "$opencodeCfg" ]; then
              mkdir -p "$(dirname "$opencodeCfg")"
              [ -f "$opencodeCfg" ] || echo '{}' > "$opencodeCfg"
              # Strip trailing commas tolerated by JSONC before passing to jq.
              ${pkgs.gnused}/bin/sed -Ez ':a;s/,([[:space:]]*[]\}])/\1/g;ta' "$opencodeCfg" \
                | ${lib.getExe pkgs.jq} --argjson mcp ${lib.escapeShellArg (builtins.toJSON opencodeMcpServers)} \
                  '.mcp = ((.mcp // {}) * $mcp)' > "$opencodeCfg.tmp" \
                && mv "$opencodeCfg.tmp" "$opencodeCfg"
            fi
          ''
        }
        ${lib.optionalString (config.programs.codex.enable && !config.programs.codex.enableMcpIntegration)
          ''
            codexCfg="${config.home.homeDirectory}/.codex/config.toml"
            if [ ! -L "$codexCfg" ]; then
              mkdir -p "$(dirname "$codexCfg")"
              touch "$codexCfg"
              ${pkgs.gnused}/bin/sed -i '/^# BEGIN HM MCP$/,/^# END HM MCP$/d' "$codexCfg"
              {
                echo "# BEGIN HM MCP"
                cat ${codexMcpToml}
                echo "# END HM MCP"
              } >> "$codexCfg"
            fi
          ''
        }
      '';
    };
  };
}
