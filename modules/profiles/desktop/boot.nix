# Fedora-like boot splash, quiet boot
{ lib, pkgs, ... }:
{
  boot.plymouth = {
    enable = true;
    theme = "bgrt";
    font = "${pkgs.noto-fonts}/share/fonts/noto/NotoSans.ttf";
    extraConfig = "UseSimpledrmNoLuks=1";
  };
  # as in Fedora's initrd: theme text in Noto Sans, the esc log in Noto Sans Mono
  boot.initrd.systemd.contents = {
    "/usr/share/fonts/Plymouth-monospace.ttf".source =
      "${pkgs.noto-fonts}/share/fonts/noto/NotoSansMono.ttf";
    "/etc/fonts/fonts.conf".text = lib.mkForce ''
      <?xml version="1.0"?>
      <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
      <fontconfig>
        <dir>/etc/plymouth/fonts</dir>
        <dir>/usr/share/fonts</dir>
        <alias binding="same">
          <family>Cantarell</family>
          <accept><family>Noto Sans</family></accept>
        </alias>
        <alias>
          <family>monospace</family>
          <prefer><family>Noto Sans Mono</family></prefer>
        </alias>
      </fontconfig>
    '';
  };
  # the kernel's builtin font has no glyphs for systemd's status symbols
  console = {
    font = "eurlatgr";
    earlySetup = true;
  };
  boot.consoleLogLevel = 3;
  boot.initrd.verbose = false;
  boot.kernelParams = [
    "quiet"
    "udev.log_level=3"
  ];
}
