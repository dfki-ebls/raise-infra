{
  inputs,
  self,
  lib',
  lib,
  ...
}:
let
  mkNixosSystem =
    cpu: extraModule:
    inputs.nixpkgs-unstable.lib.nixosSystem {
      system = null;
      specialArgs = {
        inherit inputs lib';
      };
      modules = lib.singleton (
        { modulesPath, ... }:
        {
          imports = [
            self.nixosModules.default
            "${modulesPath}/virtualisation/proxmox-image.nix"
            extraModule
          ];
          nixpkgs.hostPlatform = "${cpu}-linux";
        }
      );
    };
in
{
  imports = [
    inputs.treefmt-nix.flakeModule
  ];
  systems = import inputs.systems;

  flake = {
    nixosModules.default = ./nixos;
    nixosConfigurations = lib.genAttrs [ "x86_64" "aarch64" ] (cpu: mkNixosSystem cpu { });
    nixpkgsConfig = {
      allowUnfree = true;
      nvidia.acceptLicense = true;
    };
    overlays.default =
      final: prev:
      let
        custom = lib.packagesFromDirectoryRecursive {
          inherit (final) callPackage;
          directory = ./pkgs;
        };
      in
      {
        inherit custom;
        stable = import inputs.nixpkgs-stable {
          inherit (prev.stdenv.hostPlatform) system;
          config = self.nixpkgsConfig;
        };
        unstable = import inputs.nixpkgs-unstable {
          inherit (prev.stdenv.hostPlatform) system;
          config = self.nixpkgsConfig;
        };
      }
      // custom;
  };

  perSystem =
    {
      system,
      pkgs,
      config,
      ...
    }:
    let
      kernel = pkgs.stdenv.hostPlatform.parsed.kernel.name;
      cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;
      nixosSystem =
        if kernel == "linux" then
          mkNixosSystem cpu { }
        else
          mkNixosSystem cpu {
            virtualisation.vmVariant = {
              virtualisation.host.pkgs = import inputs.nixpkgs {
                inherit system;
                config = self.nixpkgsConfig;
                # overlays already defined in nixos config
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
        vm = nixosSystem.config.system.build.vm;
        proxmox = nixosSystem.config.system.build.VMA;
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
