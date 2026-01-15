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
  };

  perSystem =
    { system, pkgs, ... }:
    let
      kernel = pkgs.stdenv.hostPlatform.parsed.kernel.name;
      cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;
      nixosSystem =
        if kernel == "linux" then
          mkNixosSystem cpu { }
        else
          mkNixosSystem cpu {
            virtualisation.vmVariant = {
              virtualisation.host.pkgs = pkgs;
            };
          };
    in
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          nvidia.acceptLicense = true;
        };
      };
      packages = {
        default = nixosSystem.config.system.build.vm;
        proxmox = nixosSystem.config.system.build.VMA;
      };
      treefmt = {
        projectRootFile = "flake.nix";
        programs = {
          nixfmt.enable = true;
        };
      };
    };
}
