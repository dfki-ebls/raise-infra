{ lib, ... }:
{
  system.autoUpgrade = {
    enable = lib.mkDefault false;
    dates = "hourly";
    allowReboot = true;
    runGarbageCollection = true;
    rebootWindow = {
      lower = "03:00";
      upper = "05:00";
    };
  };
}
