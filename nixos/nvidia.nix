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
    # patchelf 0.19 corrupts `nvidia-smi` and segfaults it in `ld.so`.
    # Drop once https://github.com/NixOS/patchelf/pull/672 lands in nixpkgs.
    package =
      config.boot.kernelPackages.nvidiaPackages.${config.hardware.nvidia.branch}.overrideAttrs
        (prev: {
          nativeBuildInputs = prev.nativeBuildInputs ++ [ pkgs.stable.patchelf ];
        });
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
