{ lib, lib', ... }:
{
  imports = lib'.flocken.getModules ./.;

  custom = {
    rootDomain = lib.mkDefault "raise.dfki.dev";
    admin = {
      login = "mlenz";
      name = "Mirko Lenz";
      mail = "mirko.lenz@dfki.de";
    };
  };

  system.autoUpgrade = {
    enable = true;
    flake = "github:dfki-ebls/raise-infra#default";
  };

  networking.hostName = "raise";
}
