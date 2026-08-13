{
  lib,
  config,
  pkgs,
  ...
}:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
let
  imgSize = 1024;

  # `CUDA_HOME` for the JIT compilers, which otherwise look for `which nvcc` and
  # `/usr/local/cuda`. Not the bundled wheels: those are a runtime toolkit, with
  # no `libcudart.so` namelink and no driver stub to link against. Same versions
  # as the wheels, so keep both on the same CUDA line.
  cudaHome = pkgs.symlinkJoin {
    name = "vllm-cuda-home";
    # The set vLLM's own image installs for runtime JIT (docker/Dockerfile:
    # nvcc, cudart, nvrtc, cuobjdump, cublas, curand), plus what nixpkgs splits
    # out of nvcc and cudart and propagates rather than ships, propagation a
    # `symlinkJoin` drops. Flattening every output but `static` follows
    # `cudaPackages.cudatoolkit`; the headers live in ones other than `out`.
    paths = lib.concatMap (p: map (output: p.${output}) (lib.remove "static" p.outputs)) (
      with pkgs.cudaPackages_13_0;
      [
        cuda_nvcc
        cuda_cudart
        cuda_crt
        cccl
        cuda_nvrtc
        cuda_cuobjdump
        libcublas
        libcurand
      ]
    );
    # flashinfer links against `lib64` and `lib64/stubs`, a layout only the
    # retired runfile installer had.
    postBuild = "ln -s lib $out/lib64";
  };
in
lib.mkIf config.custom.enableNvidia {
  services.llmhop.vllm = {
    enable = true;
    package = pkgs.vllm;
    environmentFile = "/etc/vllm/vllm.env";
    uid = 503; # the uid the quadlet-based deployment used

    environment.CUDA_HOME = "${cudaHome}";

    # https://docs.vllm.ai/en/stable/cli/serve/
    modelSettings = {
      attention-backend = "flashinfer";
      enable-auto-tool-choice = true;
      enable-prefix-caching = true;
      gpu-memory-utilization = 0.95;
      kv-cache-dtype = "fp8";
      kv-offloading-size = 16; # GiB
      max-model-len = "128K";
      max-num-batched-tokens = 4096;
      max-num-seqs = 3;
      limit-mm-per-prompt = lib.toJSON {
        image = {
          count = 1;
          width = imgSize;
          height = imgSize;
        };
        video = {
          count = 0;
        };
        audio = {
          count = 0;
        };
      };
    };

    # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
    models."qwen3.6-27b" = {
      # The unsloth checkpoint over nvidia's: nvidia quantizes the MLPs to
      # `W4A16_NVFP4`, weight-only 4-bit, and vLLM hard-forces the Marlin
      # dequant kernel for anything weight-only regardless of GPU. unsloth
      # quantizes activations too (`nvfp4-pack-quantized`, group size 16), which
      # is what the sm120 FP4 tensor cores need, and puts the attention
      # projections on FP8 W8A8. Costs ~1.4 GiB more weights, see
      # `gpu-memory-utilization`.
      model = "unsloth/Qwen3.6-27B-NVFP4";
      port = 18206;
      # https://recipes.vllm.ai/Qwen/Qwen3.6-27B
      # https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3.5.html
      settings = {
        reasoning-parser = "qwen3";
        tool-call-parser = "qwen3_xml";
        # speculative-config = lib.toJSON {
        #   method = "mtp";
        #   num_speculative_tokens = 1;
        # };
        mm-processor-kwargs = lib.toJSON {
          images_kwargs.size = {
            longest_edge = imgSize * imgSize;
            shortest_edge = 4096;
          };
        };
      };
    };
  };
}
