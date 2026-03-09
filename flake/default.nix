{
  inputs,
  self,
  lib',
  ...
}:
let
  mkNixosSystem =
    module:
    inputs.nixpkgs-unstable.lib.nixosSystem {
      system = null;
      specialArgs = {
        inherit inputs lib';
      };
      modules = [
        self.nixosModules.default
        self.nixosModules.dfki
        module
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
    nixosConfigurations.default = mkNixosSystem {
      imports = [
        self.nixosModules.proxmox
      ];
      nixpkgs.hostPlatform = "x86_64-linux";
    };
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
      cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;
      nixosSystem = mkNixosSystem {
        imports = [
          self.nixosModules.proxmox
        ];
        nixpkgs.hostPlatform = "${cpu}-linux";
        virtualisation.vmVariant = {
          virtualisation.host.pkgs = import inputs.nixpkgs {
            inherit system;
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
      apps.default.program = config.packages.vm;
      packages = {
        default = config.packages.image;
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
