# Proton Mail bridge: imap 1143, smtp 1025, carddav 8080
{ pkgs, ... }:
{
  home.packages = [ pkgs.hydroxide ];

  systemd.user.services.hydroxide = {
    Unit.Description = "Proton Mail bridge";
    Service = {
      ExecStart = "${pkgs.hydroxide}/bin/hydroxide serve";
      Restart = "on-failure";
    };
    Install.WantedBy = [ "default.target" ];
  };
}
