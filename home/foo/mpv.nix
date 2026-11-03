{ lib, config, ... }:
{
  # nix mpv wants nixGL elsewhere
  programs.mpv = lib.mkIf config.os.isNixOS {
    enable = true;
    config = {
      # behaviour
      keep-open = true;
      save-position-on-quit = true;
      autofit-larger = "90%x90%";

      # lossless screenshot
      screenshot-format = "png";
      screenshot-high-bit-depth = true;
      screenshot-directory = "~/Pictures/mpv";
      screenshot-template = "%F-%wH.%wM.%wS.%wT-#%#00n";

      # i18n
      alang = "jpn,ja,eng,en,chi,zh,zh-CN";
      slang = "eng,en,chi,zh,zh-CN,zh-TW";
      sub-auto = "fuzzy";
      blend-subtitles = "video";
    };
  };
}
