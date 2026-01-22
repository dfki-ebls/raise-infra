{ pkgs, ... }:
let
  cpu = pkgs.stdenv.hostPlatform.parsed.cpu.name;
in
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:dfki-ebls/raise-infra#${cpu}";
    dates = "04:00";
    allowReboot = true;
    runGarbageCollection = true;
    rebootWindow = {
      lower = "03:30";
      upper = "05:00";
    };
  };

  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
  '';
}
