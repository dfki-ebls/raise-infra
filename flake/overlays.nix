{
  lib,
  inputs,
  self,
  ...
}:
{
  flake.overlays.default =
    final: prev:
    let
      custom = lib.packagesFromDirectoryRecursive {
        inherit (final) callPackage;
        directory = ../pkgs;
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
}
