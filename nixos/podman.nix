{ pkgs, ... }:
{
  environment.systemPackages = with pkgs; [
    podman-compose
  ];
  virtualisation.podman = {
    enable = true;
    # logDriver = "json-file";
    autoPrune = {
      enable = true;
      dates = "daily";
    };
  };
  virtualisation.quadlet = {
    enable = true;
    autoUpdate = {
      enable = true;
      startAt = "*-*-* 02:00:00";
    };
  };
}
