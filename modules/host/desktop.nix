{ pkgs, ... }:
{
  imports = [
    ./base
  ];

  programs.git.package = pkgs.git;
}
