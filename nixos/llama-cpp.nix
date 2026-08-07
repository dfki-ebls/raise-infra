{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
let
  qwenSettings = {
    dry-allowed-length = 16;
    dry-multiplier = 0.8;
    dry-penalty-last-n = 4096;
    dry-sequence-breaker = [
      "\n"
      ":"
      "\""
      "*"
      "/"
      "_"
      "-"
      "."
    ];
    min-p = 0.0;
    presence-penalty = 0.5;
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
      cache-ram = 0; # MiB
      cache-type-k = "q8_0";
      cache-type-v = "q8_0";
      ctx-size = 96 * 1024 * parallel;
      flash-attn = "on";
      kv-unified = false;
      mlock = true;
      mmap = false;
      n-gpu-layers = "all";
      parallel = 2;
      # keep-sorted end
    };

    models = {
      # https://unsloth.ai/docs/models/qwen3.6
      "qwen3.6-27b" = {
        enable = true;
        port = 18101;
        settings = qwenSettings // {
          hf-repo = "unsloth/Qwen3.6-27B-GGUF:UD-Q4_K_XL";
        };
      };
    };
  };
}
