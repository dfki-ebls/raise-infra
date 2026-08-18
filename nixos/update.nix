{ lib, ... }:
{
  system.autoUpgrade = {
    enable = lib.mkDefault false;
    dates = "04:00";
    allowReboot = true;
    runGarbageCollection = true;
    rebootWindow = {
      lower = "04:00";
      upper = "05:00";
    };
  };
}
