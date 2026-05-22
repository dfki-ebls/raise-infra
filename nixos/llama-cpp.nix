{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
# Workstation Blackwell is SM120 (GB20x), NOT SM100 (GB100/GB200 datacenter Blackwell).
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
      ctx-size = 32 * 1024 * parallel;
      flash-attn = "on";
      mlock = true;
      mmap = false;
      n-gpu-layers = "all";
      parallel = 4;
      # keep-sorted end
    };

    models = {
      # https://unsloth.ai/docs/models/qwen3.6
      "qwen3.6-35b-a3b" = {
        enable = false;
        port = 18101;
        settings = {
          # keep-sorted start
          hf-repo = "unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_XL";
          min-p = 0.0;
          presence-penalty = 1.0;
          reasoning = "on";
          repeat-penalty = 1.0;
          spec-draft-n-max = 3;
          spec-type = "draft-mtp";
          temperature = 1.0;
          top-k = 20;
          top-p = 0.95;
          # keep-sorted end
        };
      };
      # https://unsloth.ai/docs/models/qwen3.5
      "qwen3.5-0.8b" = {
        enable = true;
        port = 18102;
        settings = {
          # keep-sorted start
          hf-repo = "unsloth/Qwen3.5-0.8B-GGUF:UD-Q4_K_XL";
          min-p = 0.0;
          presence-penalty = 1.0;
          reasoning = "off";
          repeat-penalty = 1.0;
          spec-draft-n-max = 3;
          spec-type = "draft-mtp";
          temperature = 1.0;
          top-k = 20;
          top-p = 0.95;
          # keep-sorted end
        };
      };
    };
  };
}
