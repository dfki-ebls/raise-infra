{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf config.custom.enableNvidia {
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    open = true;
    nvidiaPersistenced = true;
    nvidiaSettings = false;
    modesetting.enable = true;
  };
  hardware.nvidia-container-toolkit.enable = true;
  nixpkgs.config.cudaSupport = true;
  environment.systemPackages = with pkgs; [
    gpustat
  ];
}
