{
  inputs,
  self,
  lib',
  lib,
  ...
}:
let

  mkNixosSystem =
    {
      cpu,
      extraModule ? { },
    }:
    inputs.nixpkgs-unstable.lib.nixosSystem {
      system = null;
      specialArgs = {
        inherit inputs lib';
      };
      modules = [
        self.nixosModules.default
        self.nixosModules.proxmox
        extraModule
        {
          nixpkgs.hostPlatform = "${cpu}-linux";
        }
      ];
    };
in
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ]
  ++ lib'.flocken.getModules ./.;
  systems = import inputs.systems;

  flake = {
    nixosConfigurations = lib.genAttrs [ "x86_64" "aarch64" ] (cpu: mkNixosSystem { inherit cpu; });
    nixpkgsConfig = {
      allowUnfree = true;
      nvidia.acceptLicense = true;
    };
  };

  perSystem =
    {
      system,
      pkgs,
      config,
      ...
    }:
    let
      nixosSystem = mkNixosSystem {
        cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;
        extraModule = {
          virtualisation.vmVariant = {
            virtualisation.host.pkgs = import inputs.nixpkgs {
              inherit system;
              config = self.nixpkgsConfig;
              # overlays already defined in nixos config
            };
          };
        };
      };
    in
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = self.nixpkgsConfig;
        overlays = [
          self.overlays.default
        ];
      };
      packages = {
        default = config.packages.vm;
        inherit (nixosSystem.config.system.build) vm image;
      }
      // pkgs.custom;
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
        };
      };
    };
}
