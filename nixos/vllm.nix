{
  lib,
  config,
  pkgs,
  ...
}:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
let
  imgSize = 1024;
in
lib.mkIf config.custom.enableNvidia {
  services.llmhop.vllm = {
    enable = true;
    package = pkgs.vllm;
    environmentFile = "/etc/vllm/vllm.env";

    # Triton probes `/sbin/ldconfig -p` for `libcuda.so.1`, which does not exist
    # on NixOS. Drop once llmhop sets this itself.
    environment.TRITON_LIBCUDA_PATH = "/run/opengl-driver/lib";

    # https://docs.vllm.ai/en/stable/cli/serve/
    modelSettings = {
      attention-backend = "flashinfer";
      enable-auto-tool-choice = true;
      gpu-memory-utilization = 0.9;
      kv-cache-dtype = "fp8";
      kv-offloading-size = 64; # GiB
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
      model = "nvidia/Qwen3.6-27B-NVFP4";
      port = 18206;
      # https://recipes.vllm.ai/Qwen/Qwen3.6-27B
      # https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3.5.html
      settings = {
        reasoning-parser = "qwen3";
        tool-call-parser = "qwen3_xml";
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
