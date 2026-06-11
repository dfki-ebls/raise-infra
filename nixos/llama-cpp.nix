{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
let
  qwenSettings = {
    min-p = 0.00;
    temperature = 1.0;
    top-k = 20;
    top-p = 0.95;
  };
in
lib.mkIf config.custom.enableNvidia {
  services.llmhop.llama-cpp = {
    enable = true;
    environmentFile = "/etc/llama-cpp/llama-cpp.env";

    # https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
    modelSettings = rec {
      # keep-sorted start
      cache-ram = 128 * 1024; # MiB
      cache-type-k = "q8_0";
      cache-type-v = "q8_0";
      ctx-size = 96 * 1024 * parallel;
      flash-attn = "on";
      mlock = true;
      mmap = false;
      n-gpu-layers = "all";
      parallel = 2;
      reasoning = "on";
      # keep-sorted end
    };

    models = {
      # https://unsloth.ai/docs/models/qwen3.6
      "qwen3.6-27b" = {
        enable = true;
        port = 18101;
        settings = qwenSettings // {
          hf-repo = "unsloth/Qwen3.6-27B-MTP-GGUF:UD-Q4_K_XL";
          spec-draft-n-max = 4;
          spec-type = "draft-mtp";
        };
      };
      "qwen3.6-35b-a3b" = {
        enable = false;
        port = 18102;
        settings = qwenSettings // {
          hf-repo = "unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_XL";
        };
      };
      # https://unsloth.ai/docs/models/qwen3.5
      "qwen3.5-0.8b" = {
        enable = true;
        port = 18103;
        settings = qwenSettings // {
          hf-repo = "unsloth/Qwen3.5-0.8B-GGUF:UD-Q4_K_XL";
          cache-ram = 1024;
          ctx-size = 4 * 1024 * qwenSettings.parallel;
        };
      };
    };
  };
}
