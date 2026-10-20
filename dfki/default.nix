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

  # DFKI operates this instance and issues Hivegent's additional terms itself.
  services.hivegent.settings.accept_terms = true;

  system.autoUpgrade = {
    enable = true;
    flake = "github:dfki-ebls/raise-infra#default";
    upgrade = false;
  };

  networking.hostName = "raise";
}
