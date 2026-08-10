{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf config.custom.enableNvidia {
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia = {
    branch = "latest";
    open = true;
    nvidiaPersistenced = true;
    nvidiaSettings = false;
    modesetting.enable = true;
  };
  hardware.nvidia-container-toolkit.enable = true;
  nixpkgs.config.cudaSupport = true;
  nixpkgs.overlays = [
    (final: prev: {
      cudaPackages = prev.cudaPackages_13_3;
    })
  ];
  environment.systemPackages = with pkgs; [
    python3Packages.gpustat
    nvtopPackages.nvidia
  ];
}
