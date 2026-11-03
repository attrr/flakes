{
  lib,
  config,
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    zsh-completions
    # falac in helpers.zsh
    ffmpeg
  ];

  home.sessionVariables = {
    GOPATH = "${config.xdg.dataHome}/go";
    ANSIBLE_HOME = "${config.xdg.configHome}/ansible";
    NIX_SSHOPTS = "-o ControlPath=~/.ssh/sockets/%r@%n-%p";
    QT_QPA_PLATFORM = "wayland";
  };

  programs.fzf.enable = true;

  programs.zsh = {
    enable = true;
    dotDir = "${config.xdg.configHome}/zsh";
    defaultKeymap = "emacs";
    autocd = true;
    history = {
      size = 10000000;
      save = 10000000;
      path = "${config.xdg.stateHome}/zsh/history";
      ignoreAllDups = true;
      append = true;
      share = false;
      # pasted scripts over 5 lines stay out of the file
      ignorePatterns = [ (lib.concatStrings (lib.replicate 5 "*\n") + "*") ];
    };
    setOptions = [
      "HIST_REDUCE_BLANKS"
      "AUTO_PUSHD"
      "PUSHD_IGNORE_DUPS"
      "PUSHD_MINUS"
      "PUSHD_TO_HOME"
      "TRANSIENT_RPROMPT"
    ];
    completionInit = ''
      autoload -Uz compinit
      mkdir -p "$XDG_CACHE_HOME/zsh"
      compinit -d "$XDG_CACHE_HOME/zsh/zcompdump"
    '';
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    shellAliases.dig = "kdig";
    plugins = [
      {
        name = "prompt";
        src = ./plugins/prompt;
        file = "prompt.zsh";
      }
      {
        name = "sudo";
        src = ./plugins/sudo;
      }
      {
        name = "par2";
        src = ./plugins/par2;
        file = "par2.zsh";
      }
    ];
    # vterm.zsh comes after the prompt plugin, to modify PROMPT
    initContent = ''
      source ${./completion.zsh}
      source ${./bindkeys.zsh}
      source ${./helpers.zsh}
      if [[ "$INSIDE_EMACS" = 'vterm' ]]; then
        source ${./vterm.zsh}
      fi
      # PackageKitCommandNotFound
      if [[ -f "/etc/profile.d/PackageKit.sh" ]]; then
        source /etc/profile.d/PackageKit.sh
      fi
    '';
  };
}
