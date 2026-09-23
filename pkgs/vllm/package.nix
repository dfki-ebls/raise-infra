{
  lib,
  pkgs,
  mkUvEnv,
  mkCudaHome,
  ffmpeg_8-headless,
  rdma-core,
  tbb_2022,
}:
let
  env = mkUvEnv {
    name = "vllm-env";
    workspaceRoot = ./.;
    buildInputs = [
      ffmpeg_8-headless # torchcodec, which supports FFmpeg 4 to 8
      rdma-core # InfiniBand for cuFile and nvshmem
      tbb_2022 # numba's threading layer
    ];
    venvOptionalLibs = [
      # Variants for the FFmpeg majors not supplied above.
      "*/torchcodec/libtorchcodec_*[!8].so"
      # nvshmem plugins for the launchers and fabrics of multi-node jobs.
      "*/nvidia/nvshmem/lib/nvshmem_*.so.3"
    ];
  };
  # `CUDA_HOME` for the JIT compilers, which otherwise look for `which nvcc` and
  # `/usr/local/cuda`. Not the bundled wheels: those are a runtime toolkit, with
  # no `libcudart.so` namelink and no driver stub to link against. The set vLLM's
  # own image installs for runtime JIT (docker/Dockerfile: nvcc, cudart, nvrtc,
  # cuobjdump, cublas, curand), on the CUDA line the lock resolved.
  cudaHome = mkCudaHome {
    name = "vllm-cuda-home";
    packages = with pkgs.${env.cudaPackagesAttr}; [
      cuda_nvcc
      cuda_cudart
      cuda_crt
      cccl
      cuda_nvrtc
      cuda_cuobjdump
      libcublas
      libcurand
    ];
  };
in
lib.lazyDerivation {
  derivation = env;
  passthru = {
    inherit cudaHome;
    inherit (env) sdists python cudaPackagesAttr;
  };
  meta = {
    description = "Python environment providing the vLLM inference server";
    homepage = "https://github.com/vllm-project/vllm";
    license = lib.licenses.asl20;
    mainProgram = "vllm";
    platforms = [ "x86_64-linux" ];
  };
}
