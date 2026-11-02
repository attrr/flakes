{ lib, config, ... }:
let
  inherit (lib.hm.gvariant) mkUint32 mkEmptyArray type;
in
{
  # from `dconf dump /`; gui changes last until the next activation
  dconf.settings = {
    "org/gnome/shell" = {
      # gnome hides it when there's only one user
      always-show-log-out = true;
      disable-user-extensions = false;
      enabled-extensions = [
        "freon@UshakovVasilii_Github.yahoo.com"
        "kimpanel@kde.org"
      ];
    };

    "org/gnome/desktop/interface".clock-format = "12h";

    # alt+space switches input sources; the window menu gives it up
    "org/gnome/desktop/input-sources" = {
      sources = [
        (lib.hm.gvariant.mkTuple [
          "xkb"
          "us"
        ])
      ];
      xkb-options = [ "terminate:ctrl_alt_bksp" ];
    };
    "org/gnome/desktop/wm/keybindings" = {
      activate-window-menu = mkEmptyArray type.string;
      switch-input-source = [ "<Alt>space" ];
      switch-input-source-backward = [ "<Shift><Alt>space" ];
    };

    "org/gnome/desktop/peripherals/mouse".left-handed = true;

    # a desktop: no blanking, no suspend
    "org/gnome/desktop/session".idle-delay = mkUint32 0;
    "org/gnome/settings-daemon/plugins/power".sleep-inactive-ac-type = "nothing";

    "org/gnome/desktop/media-handling".automount = false;
    "org/gnome/desktop/privacy".report-technical-problems = false;
    "org/gnome/system/location".enabled = false;
    "org/gnome/desktop/datetime".automatic-timezone = false;
    "org/gnome/desktop/search-providers".disabled = [ "org.gnome.Calculator.desktop" ];

    "org/gnome/nautilus/preferences".default-folder-viewer = "list-view";
    "org/gnome/nautilus/list-view".default-visible-columns = [
      "name"
      "size"
      "type"
      "date_modified"
    ];
    "org/gnome/nautilus/icon-view".default-zoom-level = "extra-large";

    "org/gtk/settings/file-chooser" = {
      clock-format = "12h";
      show-hidden = true;
      show-size-column = true;
      show-type-column = true;
    };
    "org/gtk/gtk4/settings/file-chooser" = {
      show-hidden = true;
      view-type = "list";
    };

    "org/gnome/Ptyxis".interface-style = "dark";
    "org/gnome/tweaks".show-extensions-notice = false;
  };

  # show new apps and icons without relogin
  home.activation.linkDesktopFiles = lib.hm.dag.entryAfter [ "installPackages" "linkGeneration" ] ''
    apps=${lib.escapeShellArg "${config.xdg.dataHome}/applications"}
    icons=${lib.escapeShellArg "${config.xdg.dataHome}/icons"}
    src=${lib.escapeShellArg "${config.home.profileDirectory}/share/applications"}
    run mkdir -p "$apps" "$icons"
    run touch "$icons"
    for f in "$src"/*.desktop; do
      [ -e "$f" ] || continue
      link="$apps/$(basename "$f")"
      [ -e "$link" ] || [ -L "$link" ] || run ln -s "$f" "$link"
    done
    for link in "$apps"/*.desktop; do
      if [ -L "$link" ] && [ ! -e "$link" ]; then
        case "$(readlink "$link")" in "$src"/*) run rm "$link" ;; esac
      fi
    done
  '';
}
