{ pkgs, ... }:
let
  cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;
in
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:dfki-ebls/raise-infra#${cpu}";
    dates = "hourly";
    allowReboot = true;
    runGarbageCollection = false; # makes quick iterations impossible
    rebootWindow = {
      lower = "03:00";
      upper = "05:00";
    };
  };

  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
  '';
}
