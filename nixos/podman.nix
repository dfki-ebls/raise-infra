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
}
