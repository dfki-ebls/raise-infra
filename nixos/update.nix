{ ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:dfki-ebls/raise-infra#default";
    dates = "hourly";
    allowReboot = true;
    runGarbageCollection = true;
    rebootWindow = {
      lower = "03:00";
      upper = "05:00";
    };
  };
}
