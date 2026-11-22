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
      extraGroups = if stanza.extra-groups != null then stanza.extra-groups else [ ];
      chpstSpec = lib.concatStringsSep ":" ([ user group ] ++ extraGroups);
    in
    {
      owner = "${user}:${group}";
      chpst =
        if user == "root" && group == "root" && extraGroups == [ ] then
          ""
        else
          "${coreutils}/bin/chpst -u ${lib.escapeShellArg chpstSpec} ";
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
        extra-groups = lib.mkOption {
          description = "Supplementary groups passed to `chpst -u`.";
          type = with lib.types; nullOr (listOf str);
          default = null;
        };
        path = lib.mkOption {
          description = "Extra packages/paths whose `bin` directories are prepended to `PATH`.";
          type = with lib.types; listOf (either package str);
          default = [ ];
        };
        envfile = lib.mkOption {
          description = "Path to an environment file to source (`-` prefix ignores missing file).";
          type = with lib.types; nullOr (coercedTo path toString str);
          default = null;
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
        log = lib.mkOption {
          description = "Redirect stdout/stderr via a runit log service (to syslog via `logger`, or `log.file`).";
          type = with lib.types; coercedTo bool (v: if v then { } else null) (nullOr (attrsOf anything));
          default = null;
        };
        manual-start = lib.mkOption {
          description = "Do not auto-start the service on boot (creates runit `down` file).";
          type = lib.types.nullOr lib.types.bool;
          default = null;
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
        exec-stop-post = lib.mkOption {
          description = "Program run via runit `finish` after the service exits.";
          type = lib.types.nullOr program;
          default = null;
        };
        restart-sec = lib.mkOption {
          description = "Seconds to sleep in runit `finish` before restarting a stopped service.";
          type = lib.types.nullOr lib.types.ints.unsigned;
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
        runlevel = lib.mkOption {
          description = ''Finit runlevel string; `"S"` runs only once at boot (`::sysinit:`), others run during activation.'';
          type = lib.types.nullOr lib.types.str;
          default = null;
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
  bootTasks = lib.filter (t: t.value.runlevel == "S") enabledTasks;
  activationTasks = lib.filter (t: t.value.runlevel != "S") enabledTasks;

  mkTaskSnippet =
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
      ) || echo "ERROR: finit.tasks.${name} failed (exit $?); continuing" >&2
    '';

  sysinitScript = pkgs.writeScript "sysinit" ''
    #!${coreutils}/bin/sh
    ${lib.concatMapStringsSep "\n" mkTaskSnippet bootTasks}
  '';

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

  mkEnvFileSnippet =
    envfile:
    lib.optionalString (envfile != null) (
      let
        optional = lib.hasPrefix "-" envfile;
        path = lib.removePrefix "-" envfile;
      in
      if optional then
        ''
          if [ -r ${lib.escapeShellArg path} ]; then
            set -a
            . ${lib.escapeShellArg path}
            set +a
          fi
        ''
      else
        ''
          set -a
          . ${lib.escapeShellArg path}
          set +a
        ''
    );

  mkStanzaEnvAndDirs =
    svc:
    let
      inherit (runAs svc) owner;
      extraPath = mkBinPath (svc.path ++ config.finit.path);
      mergedEnv = config.finit.environment // svc.environment;
    in
    ''
      export PATH=${
        lib.escapeShellArg (
          lib.optionalString (extraPath != "") "${extraPath}:" + "${coreutils}/bin:${systemPath}"
        )
      }
      ${mkEnvFileSnippet svc.envfile}
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (
          k: v: lib.optionalString (v != null) "export ${k}=${lib.escapeShellArg (toString v)}"
        ) mergedEnv
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

  mkFinishScript =
    name: svc:
    pkgs.writeScript "${name}-finish" ''
      #!${coreutils}/bin/sh
      ${lib.optionalString (svc.exec-stop-post != null) "${svc.exec-stop-post} || true"}
      ${lib.optionalString (svc.restart-sec != null && svc.restart-sec > 0) "${coreutils}/bin/sleep ${toString svc.restart-sec}"}
    '';

  mkLogScript =
    name: svc:
    let
      tag = svc.log.tag or name;
      logCmd =
        if svc.log ? file then
          "${coreutils}/bin/cat >> ${lib.escapeShellArg (toString svc.log.file)}"
        else
          "${coreutils}/bin/logger -t ${lib.escapeShellArg tag}";
    in
    pkgs.writeScript "${name}-log-run" ''
      #!${coreutils}/bin/sh
      exec ${logCmd}
    '';

  servicesDir = pkgs.runCommandLocal "runit-services" { } ''
    mkdir -p "$out"
    ${lib.concatStringsSep "\n" (
      lib.mapAttrsToList (
        name: svc:
        let
          hasFinish = svc.exec-stop-post != null || (svc.restart-sec != null && svc.restart-sec > 0);
        in
        ''
          mkdir -p "$out/${name}"
          ln -s ${mkRunScript name svc} "$out/${name}/run"
          ${lib.optionalString hasFinish ''
            ln -s ${mkFinishScript name svc} "$out/${name}/finish"
          ''}
          ${lib.optionalString (svc.manual-start == true) ''
            : > "$out/${name}/down"
          ''}
          ${lib.optionalString (svc.log != null) ''
            mkdir -p "$out/${name}/log"
            ln -s ${mkLogScript name svc} "$out/${name}/log/run"
          ''}
        ''
      ) enabledServices
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
        ${lib.optionalString (bootTasks != [ ]) "::sysinit:${sysinitScript}"}
        ::respawn:${runsvdirWrapper}
        ::shutdown:${coreutils}/bin/sv down /run/service/*
      '';
    };

    finit.tmpfiles.rules = lib.concatLists (
      lib.mapAttrsToList (
        name: svc:
        [ "d /run/service/${name}/supervise 0755 - -" ]
        ++ lib.optional (svc.log != null) "d /run/service/${name}/log/supervise 0755 - -"
      ) enabledServices
    );

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

    # 2. Execute oneshot `finit.tasks.*` and `finit.run.*` (except `runlevel = "S"`) before starting/restarting services
    system.activation.scripts.tasks = {
      deps = [
        "specialfs"
        "users"
        "etc"
        "tmpfiles"
      ];
      text = lib.concatMapStringsSep "\n" mkTaskSnippet activationTasks;
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
          if [ -L "$svc/finish" ]; then
            ln -sfn "$(readlink "$svc/finish")" "/run/service/$name/finish"
          else
            rm -f "/run/service/$name/finish"
          fi
          if [ -e "$svc/down" ]; then
            : > "/run/service/$name/down"
          else
            rm -f "/run/service/$name/down"
          fi
          if [ -L "$svc/log/run" ]; then
            mkdir -p "/run/service/$name/log"
            prev_log=$(readlink "/run/service/$name/log/run" 2>/dev/null || true)
            next_log=$(readlink "$svc/log/run" 2>/dev/null || true)
            ln -sfn "$next_log" "/run/service/$name/log/run"
            if [ -n "$prev_log" ] && [ "$prev_log" != "$next_log" ] && [ -e "/run/service/$name/log/supervise/ok" ]; then
              ${coreutils}/bin/sv restart "/etc/service/$name/log" || true
            fi
          elif [ -d "/run/service/$name/log" ]; then
            ${coreutils}/bin/sv down "/etc/service/$name/log" 2>/dev/null || true
            rm -rf "/run/service/$name/log"
          fi
          ln -sfn "/run/service/$name" "/etc/service/$name"
          if [ -n "$prev" ] && [ "$prev" != "$next" ] && [ -e "/run/service/$name/supervise/ok" ]; then
            ${coreutils}/bin/sv restart "/etc/service/$name" || true
          fi
        done
      '';
    };
  };
}
