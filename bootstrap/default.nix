# Bootstrap artifacts, exposed as legacyPackages.<system>.bootstrap:
#   rescue.default   generic rescue, keys only via ssh_key= on the cmdline
#   rescue.<host>    rescue preconfigured from ctx (+ rescue/hosts/<host>.nix if present)
#   images.<name>    scripts that write <name>'s image into $PWD, as its host (./identity-image.nix)
{
  nixpkgs,
  self,
  ctx,
  system,
}:
let
  inherit (nixpkgs) lib;
  pkgs = nixpkgs.legacyPackages.${system};

  mkRescue = import ./rescue { inherit nixpkgs system; };
  identityImage = import ./identity-image.nix { inherit lib pkgs; };

  hosts = lib.filterAttrs (_: a: a.ctx.metadata.arch == system) (
    lib.mapAttrs (_: m: { inherit (m._module.args) ctx global; }) (
      removeAttrs ctx.nixosModules [ "default" ]
    )
  );
in
{
  inherit mkRescue;

  rescue = {
    default = mkRescue { };
  }
  // lib.mapAttrs (
    name: args:
    mkRescue {
      specialArgs = args;
      modules = lib.filter builtins.pathExists [
        ./rescue/ctx.nix
        ./rescue/hosts/${name}.nix
      ];
    }
  ) hosts;

  # every config whose host has an ssh host key in ctx vars, as that host;
  # <host>+<variant> configs included (same identity), so never run both at once
  images =
    let
      vars = name: ../ctx/vars + "/${builtins.head (lib.splitString "+" name)}";
      hostKey = name: vars name + "/ssh-host-key/ssh_host_ed25519_key";
      disko = lib.filterAttrs (
        name: cfg: (cfg.config.disko.devices.disk or { }) != { } && builtins.pathExists (hostKey name)
      ) self.nixosConfigurations;
      containers = lib.filterAttrs (
        name: cfg: cfg.config.boot.isContainer && !(cfg.config ? finit) && builtins.pathExists (hostKey name)
      ) self.nixosConfigurations;
      minimalContainers = lib.filterAttrs (
        name: cfg: (cfg.config ? finit) && builtins.pathExists (hostKey name)
      ) self.nixosConfigurations;
    in
    lib.mapAttrs (
      name: cfg:
      identityImage.disko {
        inherit name;
        nixos = cfg;
        vars = vars name;
        # <host>+vm configs run as VMs, the rest get dd'ed from rescue
        format = if lib.hasSuffix "+vm" name then "qcow2" else "raw.zst";
      }
    ) disko
    // lib.mapAttrs (
      name: cfg:
      identityImage.tarball {
        inherit name;
        nixos = cfg;
        vars = vars name;
      }
    ) containers
    // lib.mapAttrs (
      name: cfg:
      identityImage.tarball.minimal {
        inherit name;
        nixos = cfg;
        vars = vars name;
      }
    ) minimalContainers
    // {
      # the Pi boots an sd image instead
      yata = identityImage.sd rec {
        name = "yata";
        nixos = self.nixosConfigurations.yata.extendModules { modules = [ ./images/yata.nix ]; };
        vars = vars name;
      };
      # the Pixel's userdata, a repart image
      flame =
        let
          nixos = self.nixosConfigurations.flame.extendModules { modules = [ ./images/flame.nix ]; };
        in
        identityImage.sd rec {
          name = "flame";
          inherit nixos;
          vars = vars name;
          image = "${nixos.config.system.build.image}/${nixos.config.image.filePath}";
          sectorSize = 4096;
        };
    };
}
