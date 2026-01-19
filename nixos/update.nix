{ ... }:
{
  system.autoUpgrade = {
    enable = true;
    flake = "github:dfki-ebls/raise-infra";
    dates = "04:00";
    allowReboot = true;
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
