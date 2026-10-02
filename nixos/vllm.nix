{
  lib,
  config,
  pkgs,
  ...
}:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
let
  imgSize = 1024;
  model = "unsloth/Qwen3.8-27B-NVFP4";
  # Shared by the generating worker and its detector.
  # No MTP, since vLLM skips context deduplication on speculative tokens,
  # which makes Gumbel watermarking prone to repetition loops.
  watermark.algorithm = "gumbel";
  # Optional, read through `HF_TOKEN_PATH` and skipped while missing.
  credentials."huggingface.token" = { };
in
lib.mkIf config.custom.enableNvidia {
  # llmhop grants it to every workload with a `watermark`.
  custom.credstore."vllm.watermark-key" = "od -An -N8 -tu8 /dev/urandom | tr -d ' '";

  services.llmhop.vllm = {
    enable = true;
    package = pkgs.vllm;
    uid = 503;

    environment = {
      CUDA_HOME = "${pkgs.vllm.cudaHome}";
      HF_TOKEN_PATH = "%d/huggingface.token";
    };

    # https://docs.vllm.ai/en/stable/cli/serve/
    modelSettings = {
      attention-backend = "flashinfer";
      enable-auto-tool-choice = true;
      enable-prefix-caching = true;
      gpu-memory-utilization = 0.95;
      kv-cache-dtype = "fp8";
      kv-offloading-size = 16; # GiB
      max-model-len = "144K";
      max-num-batched-tokens = 4096;
      max-num-seqs = 2;
      limit-mm-per-prompt = {
        image = {
          # image.count * image.size * max-num-seqs <= max-num-batched-tokens
          count = 2;
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
    models."qwen3.8-27b" = {
      inherit model watermark credentials;
      # https://unsloth.ai/docs/models/qwen3.8
      # https://recipes.vllm.ai/Qwen/Qwen3.8-27B
      # https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3.5.html
      settings = {
        reasoning-parser = "qwen3";
        tool-call-parser = "qwen3_xml";
        override-generation-config = {
          min_p = 0.0;
          presence_penalty = 0.0;
          repetition_penalty = 1.0;
          temperature = 1.0;
          top_k = 20;
          top_p = 0.95;
        };
        mm-processor-kwargs = {
          images_kwargs.size = {
            longest_edge = imgSize * imgSize;
            shortest_edge = 4096;
          };
        };
      };
    };

    detectors.watermark = {
      tokenizer = model;
      inherit watermark credentials;
    };
  };
}
