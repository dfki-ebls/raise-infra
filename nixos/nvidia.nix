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
  # Load at boot, `security.lockKernelModules` blocks on-demand loading later.
  boot.kernelModules = [
    "nvidia"
    "nvidia_modeset"
    "nvidia_drm"
    "nvidia_uvm"
  ];
  hardware.nvidia-container-toolkit.enable = true;
  nixpkgs.config.cudaSupport = true;
  environment.systemPackages = with pkgs; [
    python3Packages.gpustat
    nvtopPackages.nvidia
  ];
}
