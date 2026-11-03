{
  programs.git = {
    enable = true;
    # git comes from the system
    package = null;
    lfs.enable = true;
    signing = {
      format = "ssh";
      key = "/home/foo/.ssh/keyrings/persist/sign.pub";
      signByDefault = true;
    };
    settings = {
      user = {
        name = "attrr";
        email = "110731994+attrr@users.noreply.github.com";
      };
    };
  };
}
