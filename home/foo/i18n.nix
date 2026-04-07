{ pkgs, ... }:
{
  i18n.inputMethod.enable = true;
  i18n.inputMethod.type = "fcitx5";
  i18n.inputMethod.fcitx5 = {
    settings = {
      inputMethod = {
        "Groups/0" = {
          Name = "Default";
          "Default Layout" = "us";
          DefaultIM = "keyboard-us";
        };
        "Groups/0/Items/0".Name = "keyboard-us";
        "Groups/0/Items/1".Name = "anthy";
        "Groups/0/Items/2".Name = "pinyin";
      };
      globalOptions = {
        Behavior.ShareInputState = "All";
        "Hotkey/TriggerKeys"."0" = "Super+space";
        "Hotkey/EnumerateGroupForwardKeys"."0" = "Super+space";
        "Hotkey/EnumerateGroupBackwardKeys"."0" = "Shift+Super+space";
      };
      addons.pinyin.globalSection = {
        CloudPinyinEnabled = false;
        KeepCloudPinyinPlaceHolder = false;
      };
    };
    addons = with pkgs; [
      kdePackages.fcitx5-chinese-addons
      fcitx5-pinyin-zhwiki
      fcitx5-pinyin-moegirl
      fcitx5-anthy
      fcitx5-gtk
    ];
  };

  allowUnfree.packages = [
    pkgs.fcitx5-pinyin-moegirl
  ];
}
