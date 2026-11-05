{
  lib,
  inputs,
  ...
}:
{
  flake.overlays.default =
    final: prev:
    let
      custom = lib.packagesFromDirectoryRecursive {
        callPackage = final.newScope {
          inherit (inputs.llmhop.legacyPackages.${prev.stdenv.hostPlatform.system})
            mkUvEnv
            mkCudaHome
            ;
        };
        directory = ../pkgs;
      };
    in
    { inherit custom; } // custom;
}
