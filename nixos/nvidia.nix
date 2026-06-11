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
      # cuda_cccl was renamed to cccl in the CUDA 13.3 redist and is not yet
      # packaged in nixpkgs, drop once https://github.com/NixOS/nixpkgs/pull/528773 lands
      _cuda = prev._cuda.extend (
        _: prevAttrs: {
          extensions = prevAttrs.extensions ++ [
            (
              _: cudaPrev:
              lib.optionalAttrs (cudaPrev.cudaAtLeast "13.3") {
                cuda_cccl = cudaPrev.cuda_cccl.override (args: {
                  buildRedist = drvArgs: args.buildRedist (drvArgs // { pname = "cccl"; });
                });
              }
            )
          ];
        }
      );
      # final (not prev) so cudaPackages_13_3 sees the _cuda extension above
      cudaPackages = final.cudaPackages_13_3;
    })
  ];
  environment.systemPackages = with pkgs; [
    python3Packages.gpustat
    nvtopPackages.nvidia
  ];
}
