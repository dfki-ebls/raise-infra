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
        callPackage = final.newScope {
          inherit (inputs.llmhop.legacyPackages.${prev.stdenv.hostPlatform.system}) mkUvEnv;
        };
        directory = ../pkgs;
      };
    in
    {
      inherit custom;
      stable = import inputs.nixpkgs-stable {
        inherit (prev.stdenv.hostPlatform) system;
        config = self.nixpkgsConfig;
      };
      unstable = import inputs.nixpkgs {
        inherit (prev.stdenv.hostPlatform) system;
        config = self.nixpkgsConfig;
      };
    }
    // custom;
}
