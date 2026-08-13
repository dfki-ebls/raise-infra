{
  lib,
  mkUvEnv,
  python314,
  ffmpeg-headless,
  rdma-core,
  tbb_2022,
  z3,
}:
# vLLM ships no one-derivation-fits-all build, so the version is pinned in the
# uv workspace next to this file: edit pyproject.toml and run `uv lock`.
# The lock resolves linux wheels only, so the environment does not even
# evaluate elsewhere; `lazyDerivation` keeps `meta` readable regardless, which
# is what lets the flake outputs filter it out by platform.
let
  env = mkUvEnv {
    name = "vllm-env";
    workspaceRoot = ./.;
    python = python314;
    buildInputs = [
      ffmpeg-headless # torchcodec
      rdma-core # nvshmem's InfiniBand transport
      tbb_2022 # numba's threading layer
      z3.lib # tilelang's TVM analyzer
    ];
  };
in
lib.lazyDerivation {
  derivation = env;
  # Toolkit root of the bundled CUDA wheels. deep_gemm and flashinfer both JIT
  # kernels through nvcc and locate it via `CUDA_HOME`, falling back to `which
  # nvcc` and `/usr/local/cuda` — neither of which exists on NixOS.
  passthru.cudaHome = "${env}/${python314.sitePackages}/nvidia/cu13";
  meta = {
    description = "Python environment providing the vLLM inference server";
    homepage = "https://github.com/vllm-project/vllm";
    license = lib.licenses.asl20;
    mainProgram = "vllm";
    platforms = lib.platforms.linux;
  };
}
