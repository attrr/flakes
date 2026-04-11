{ pkgs, ... }@args:
let
  base = import ../../modules/host/base args;
  settings = base.programs.htop.settings;
in
{
  programs.htop = {
    enable = true;
    settings = settings // {
      left_meters = map (x: if x == "AllCPUs" then "AllCPUs2" else x) settings.left_meters;
    };
  };
}
