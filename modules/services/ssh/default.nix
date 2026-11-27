{
  os =
    { config, lib, ... }:
    let
      cfg = config.services.openssh;
    in
    {
      options.services.openssh = {
        users = lib.mkOption {
          description = "Attrset of users allowed to SSH, mapping to their keys.";
          default = { };
          type = lib.types.attrsOf (
            lib.types.submodule {
              options.authorizedKeys = lib.mkOption {
                type = lib.types.listOf lib.types.str;
                default = [ ];
              };
            }
          );
        };
        lockRootLogin = lib.mkEnableOption "disable root login";
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = builtins.all (user: user.authorizedKeys != [ ]) (builtins.attrValues cfg.users);
            message = "services.openssh.authorizedKeys must not be empty.";
          }
        ];

        users.users = lib.mapAttrs (_: v: {
          isNormalUser = true;
          extraGroups = [ "wheel" ];
          openssh.authorizedKeys.keys = v.authorizedKeys;
        }) cfg.users;

        services.openssh.settings = {
          PasswordAuthentication = lib.mkDefault false;
          KbdInteractiveAuthentication = lib.mkDefault false;
          PermitRootLogin = lib.mkDefault "no";
          AllowUsers = builtins.attrNames cfg.users;
        };
      };
    };

  nixos =
    { config, lib, ... }:
    let
      cfg = config.services.openssh;
    in
    {
      config = lib.mkIf cfg.enable {
        users.mutableUsers = lib.mkIf cfg.lockRootLogin false;
        users.users.root.hashedPassword = lib.mkIf cfg.lockRootLogin "!";

        services.fail2ban.enable = lib.mkDefault true;
        services.endlessh = lib.mkIf (!builtins.elem 22 cfg.ports) {
          enable = lib.mkDefault true;
          port = 22;
          openFirewall = true;
        };
      };
    };

  finix =
    { config, lib, ... }:
    let
      cfg = config.services.openssh;
    in
    {
      config = lib.mkIf cfg.enable {
        users.users.root.password = lib.mkIf cfg.lockRootLogin "!";
      };
    };
}
