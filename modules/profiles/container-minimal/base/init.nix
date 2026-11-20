# Translates Finix's `finit.{services,tasks,run,tmpfiles}` options into BusyBox `init` + `runit` (`runsvdir`)
# and `system.activation.scripts`, allowing upstream Finix service modules to run without `finit` as PID 1.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  coreutils = config.programs.coreutils.package;

  pathOrStr = with lib.types; coercedTo path (x: "${x}") str;
  program = lib.types.coercedTo (
    lib.types.package
    // {
      check = v: v.type or null == "derivation" && v ? meta.mainProgram;
    }
  ) lib.getExe pathOrStr;

  # Default search path appended after a service's own `path` and busybox.
  systemPath = "/run/current-system/sw/bin:/run/current-system/sw/sbin:/bin:/sbin";

  # `chpst` prefix and `user:group` owner for a stanza (root runs without `chpst`).
  runAs =
    stanza:
    let
      user = if stanza.user != null then stanza.user else "root";
      group = if stanza.group != null then stanza.group else user;
    in
    {
      owner = "${user}:${group}";
      chpst =
        if user == "root" && group == "root" then
          ""
        else
          "${coreutils}/bin/chpst -u ${lib.escapeShellArg "${user}:${group}"} ";
    };

  mkBinPath =
    list:
    lib.concatStringsSep ":" (
      map (p: if lib.isDerivation p then "${lib.getBin p}/bin" else "${toString p}/bin") list
    );

  stanzaOpts =
    { config, name, ... }:
    {
      freeformType = lib.types.attrsOf lib.types.anything;
      options = {
        enable = lib.mkOption {
          description = "Whether this stanza is active.";
          type = lib.types.bool;
          default = true;
        };
        description = lib.mkOption {
          description = "Human-readable summary (informational only).";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        user = lib.mkOption {
          description = "User to run as (default `root`).";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        group = lib.mkOption {
          description = "Group to run as (default: same as `user`).";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        path = lib.mkOption {
          description = "Extra packages/paths whose `bin` directories are prepended to `PATH`.";
          type = with lib.types; listOf (either package str);
          default = [ ];
        };
        environment = lib.mkOption {
          description = "Environment variables exported before running the command (`null` skips).";
          type = lib.types.attrsOf (
            lib.types.nullOr (
              lib.types.oneOf [
                lib.types.str
                lib.types.int
                lib.types.bool
              ]
            )
          );
          default = { };
        };
        workingDirectory = lib.mkOption {
          description = "Directory to `cd` into before running the command.";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        state-dir = lib.mkOption {
          description = "Directory under `/var/lib` (or absolute) exported as `STATE_DIRECTORY`.";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        state-dir-mode = lib.mkOption {
          description = "Mode of `state-dir`.";
          type = lib.types.str;
          default = "0755";
        };
        runtime-dir = lib.mkOption {
          description = "Directory under `/run` (or absolute) exported as `RUNTIME_DIRECTORY`.";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        runtime-dir-mode = lib.mkOption {
          description = "Mode of `runtime-dir`.";
          type = lib.types.str;
          default = "0755";
        };
        cache-dir = lib.mkOption {
          description = "Directory under `/var/cache` (or absolute) exported as `CACHE_DIRECTORY`.";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        cache-dir-mode = lib.mkOption {
          description = "Mode of `cache-dir`.";
          type = lib.types.str;
          default = "0755";
        };
        logs-dir = lib.mkOption {
          description = "Directory under `/var/log` (or absolute) exported as `LOGS_DIRECTORY`.";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        logs-dir-mode = lib.mkOption {
          description = "Mode of `logs-dir`.";
          type = lib.types.str;
          default = "0755";
        };
        config-dir = lib.mkOption {
          description = "Directory under `/etc` (or absolute) exported as `CONFIGURATION_DIRECTORY`.";
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
        config-dir-mode = lib.mkOption {
          description = "Mode of `config-dir`.";
          type = lib.types.str;
          default = "0755";
        };
        exec-start-pre = lib.mkOption {
          description = "Program run (as root, after env/dirs setup) before the command.";
          type = lib.types.nullOr program;
          default = null;
        };
        command = lib.mkOption {
          description = "Program to exec; wrapped in `chpst` when `user`/`group` is non-root.";
          type = lib.types.nullOr program;
          default = null;
        };
        script = lib.mkOption {
          description = "Shell snippet; when non-empty it replaces `command`.";
          type = lib.types.lines;
          default = "";
        };
        reload-triggers = lib.mkOption {
          description = "Values embedded in the run script so changes restart the service.";
          type = with lib.types; listOf (either str path);
          default = [ ];
        };
        priority = lib.mkOption {
          description = "Task ordering (lower runs first).";
          type = lib.types.int;
          default = 1000;
        };
      };

      config.command = lib.mkIf (config.script != "") (
        lib.mkForce (
          pkgs.writeScript "${name}-script" ''
            #!${coreutils}/bin/sh
            set -eu
            ${config.script}
          ''
        )
      );
    };

  enabledServices = lib.filterAttrs (_: s: s.enable) config.finit.services;
  enabledTasks = lib.sort (a: b: a.value.priority < b.value.priority) (
    lib.attrsToList (lib.filterAttrs (_: t: t.enable) (config.finit.tasks // config.finit.run))
  );

  mkDirSnippet =
    base: rel: mode: owner: envVar:
    lib.optionalString (rel != null) (
      let
        dir = if lib.hasPrefix "/" rel then rel else "${base}/${rel}";
      in
      ''
        mkdir -p ${lib.escapeShellArg dir}
        ${lib.optionalString (owner != null) "chown ${lib.escapeShellArg owner} ${lib.escapeShellArg dir}"}
        chmod ${mode} ${lib.escapeShellArg dir}
        export ${envVar}=${lib.escapeShellArg dir}
      ''
    );

  mkStanzaEnvAndDirs =
    svc:
    let
      inherit (runAs svc) owner;
      extraPath = mkBinPath svc.path;
    in
    ''
      export PATH=${
        lib.escapeShellArg (
          lib.optionalString (extraPath != "") "${extraPath}:" + "${coreutils}/bin:${systemPath}"
        )
      }
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          k: v: lib.optionalString (v != null) "export ${k}=${lib.escapeShellArg (toString v)}"
        ) svc.environment
      )}
      ${mkDirSnippet "/var/lib" svc.state-dir svc.state-dir-mode owner "STATE_DIRECTORY"}
      ${mkDirSnippet "/run" svc.runtime-dir svc.runtime-dir-mode owner "RUNTIME_DIRECTORY"}
      ${mkDirSnippet "/var/cache" svc.cache-dir svc.cache-dir-mode owner "CACHE_DIRECTORY"}
      ${mkDirSnippet "/var/log" svc.logs-dir svc.logs-dir-mode owner "LOGS_DIRECTORY"}
      ${mkDirSnippet "/etc" svc.config-dir svc.config-dir-mode null "CONFIGURATION_DIRECTORY"}
      ${lib.optionalString (svc.workingDirectory != null) "cd ${lib.escapeShellArg svc.workingDirectory}"}
      ${lib.optionalString (svc.exec-start-pre != null) "${svc.exec-start-pre}"}
    '';

  mkRunScript =
    name: svc:
    let
      inherit (runAs svc) chpst;
    in
    pkgs.writeScript "${name}-run" ''
      #!${coreutils}/bin/sh
      exec 2>&1
      set -eu
      ${mkStanzaEnvAndDirs svc}
      # reload-triggers: ${lib.concatStringsSep " " (map toString svc.reload-triggers)}
      exec ${chpst}${svc.command}
    '';

  servicesDir = pkgs.runCommandLocal "runit-services" { } ''
    mkdir -p "$out"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (name: svc: ''
        mkdir -p "$out/${name}"
        ln -s ${mkRunScript name svc} "$out/${name}/run"
      '') enabledServices
    )}
  '';

  runsvdirWrapper = pkgs.writeScript "runsvdir-wrapper" ''
    #!${coreutils}/bin/sh
    export PATH=${coreutils}/bin:${systemPath}
    exec ${coreutils}/bin/runsvdir -P /etc/service
  '';
in
{
  options = {
    boot.init = lib.mkOption {
      type = lib.types.path;
      default = pkgs.writeScript "init" ''
        #!${coreutils}/bin/sh
        sys=$(${coreutils}/bin/readlink -f /nix/var/nix/profiles/system)
        "$sys/activate" || true
        exec ${coreutils}/bin/init "$@"
      '';
      description = "PID 1 entrypoint linked at `$toplevel/init`.";
    };

    finit = {
      path = lib.mkOption {
        type = with lib.types; listOf (either path str);
        default = [ ];
      };
      environment = lib.mkOption {
        type = with lib.types; attrsOf str;
        default = { };
      };
      tmpfiles.rules = lib.mkOption {
        type = with lib.types; listOf str;
        default = [ ];
        description = "`tmpfiles.d(5)` rules (`d`, `f`, `L+`, `R!`) evaluated during activation.";
      };
      services = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule stanzaOpts);
        default = { };
        description = "Finix service stanzas translated into runit services under `/etc/service/<name>`.";
      };
      tasks = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule stanzaOpts);
        default = { };
        description = "Finix oneshot task stanzas executed during system activation.";
      };
      run = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule stanzaOpts);
        default = { };
        description = "Finix synchronous oneshot stanzas executed during system activation.";
      };
      ttys = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
      };
    };
  };

  config = {
    environment.variables.SVDIR = "/etc/service";

    environment.etc = {
      inittab.text = ''
        ::respawn:${runsvdirWrapper}
        ::shutdown:${coreutils}/bin/sv down /run/service/*
      '';
    };

    # 1. Execute `finit.tmpfiles.rules` (`d`, `f`, `L+`, `R!`)
    system.activation.scripts.tmpfiles = {
      deps = [
        "specialfs"
        "users"
        "etc"
      ];
      text = lib.concatMapStrings (
        rule:
        let
          parts = lib.filter (s: s != "") (lib.splitString " " rule);
          kind = lib.elemAt parts 0;
          target = lib.elemAt parts 1;
          mode = if lib.length parts > 2 && lib.elemAt parts 2 != "-" then lib.elemAt parts 2 else null;
          user = if lib.length parts > 3 && lib.elemAt parts 3 != "-" then lib.elemAt parts 3 else null;
          group = if lib.length parts > 4 && lib.elemAt parts 4 != "-" then lib.elemAt parts 4 else null;
          arg = if lib.length parts > 6 && lib.elemAt parts 6 != "-" then lib.elemAt parts 6 else null;
        in
        if kind == "d" || kind == "D" then
          ''
            mkdir -p ${lib.escapeShellArg target}
            ${lib.optionalString (mode != null) "chmod ${mode} ${lib.escapeShellArg target}"}
            ${lib.optionalString (user != null)
              "chown ${user}${lib.optionalString (group != null) ":${group}"} ${lib.escapeShellArg target}"
            }
          ''
        else if kind == "f" then
          ''
            mkdir -p "$(dirname ${lib.escapeShellArg target})"
            [ -e ${lib.escapeShellArg target} ] || : > ${lib.escapeShellArg target}
            ${lib.optionalString (mode != null) "chmod ${mode} ${lib.escapeShellArg target}"}
            ${lib.optionalString (user != null)
              "chown ${user}${lib.optionalString (group != null) ":${group}"} ${lib.escapeShellArg target}"
            }
          ''
        else if (kind == "L" || kind == "L+") && arg != null then
          ''
            mkdir -p "$(dirname ${lib.escapeShellArg target})"
            ${lib.optionalString (kind == "L+") ''
              [ ! -e ${lib.escapeShellArg target} ] || [ -L ${lib.escapeShellArg target} ] || rm -rf ${lib.escapeShellArg target}
            ''}
            ln -sfn ${lib.escapeShellArg arg} ${lib.escapeShellArg target}
          ''
        else if kind == "z" then
          ''
            if [ -e ${lib.escapeShellArg target} ]; then
              ${lib.optionalString (mode != null) "chmod ${mode} ${lib.escapeShellArg target}"}
              ${lib.optionalString (user != null)
                "chown ${user}${lib.optionalString (group != null) ":${group}"} ${lib.escapeShellArg target}"
              }
            fi
          ''
        else if kind == "R" || kind == "R!" then
          ''
            rm -rf ${lib.escapeShellArg target}
          ''
        else
          ""
      ) config.finit.tmpfiles.rules;
    };

    # 2. Execute oneshot `finit.tasks.*` and `finit.run.*` before starting/restarting services
    system.activation.scripts.tasks = {
      deps = [
        "specialfs"
        "users"
        "etc"
        "tmpfiles"
      ];
      text = lib.concatMapStringsSep "\n" (
        { name, value }:
        let
          task = value;
          inherit (runAs task) chpst;
        in
        ''
          (
            set -eu
            ${mkStanzaEnvAndDirs task}
            ${chpst}${task.command}
          ) || echo "ERROR: finit.tasks.${name} failed (exit $?); continuing activation" >&2
        ''
      ) enabledTasks;
    };

    # 3. Reconcile `/etc/service/<name>` -> `/run/service/<name>` and restart changed services
    system.activation.scripts.services = {
      deps = [
        "specialfs"
        "users"
        "etc"
        "tmpfiles"
        "tasks"
      ];
      text = ''
        mkdir -p /etc/service /run/service
        for link in /etc/service/*; do
          [ -L "$link" ] || continue
          name=$(basename "$link")
          if [ ! -d "${servicesDir}/$name" ]; then
            ${coreutils}/bin/sv down "$link" 2>/dev/null || true
            rm -f "$link"
            rm -rf "/run/service/$name"
          fi
        done
        for svc in "${servicesDir}"/*; do
          [ -d "$svc" ] || continue
          name=$(basename "$svc")
          mkdir -p "/run/service/$name"
          prev=$(readlink "/run/service/$name/run" 2>/dev/null || true)
          next=$(readlink "$svc/run" 2>/dev/null || true)
          ln -sfn "$next" "/run/service/$name/run"
          ln -sfn "/run/service/$name" "/etc/service/$name"
          if [ -n "$prev" ] && [ "$prev" != "$next" ] && [ -e "/run/service/$name/supervise/ok" ]; then
            ${coreutils}/bin/sv restart "/etc/service/$name" || true
          fi
        done
      '';
    };
  };
}
