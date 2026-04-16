{ lib, config, ... }:
lib.mkIf config.custom.enableNvidia {
  custom.vllm = {
    enable = true;
    environmentFile = "/etc/vllm/vllm.env";
    models = {
      # https://docs.vllm.ai/projects/recipes/en/latest/Google/Gemma4.html
      # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
      "gemma4-31b" = {
        model = "RedHatAI/gemma-4-31B-it-NVFP4";
        tag = "gemma4-cu130";
        port = 18001;
        extraArgs = {
          async-scheduling = true;
          enable-auto-tool-choice = true;
          enable-prefix-caching = true;
          enforce_eager = true;
          gpu-memory-utilization = 0.8;
          kv-cache-dtype = "fp8";
          max-model-len = 16 * 1024;
          max-num-seqs = 2;
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          default-chat-template-kwargs = lib.toJSON {
            enable_thinking = true;
          };
          limit-mm-per-prompt = lib.toJSON {
            image = 2;
            audio = 0;
            video = 0;
          };
        };
      };
      "gemma4-e2b" = {
        model = "google/gemma-4-E2B-it";
        tag = "gemma4-cu130";
        port = 18002;
        extraArgs = {
          async-scheduling = true;
          enable-prefix-caching = false;
          enforce_eager = true;
          gpu-memory-utilization = 0.1;
          kv-cache-dtype = "fp8";
          max-model-len = 4 * 1024;
          max-num-seqs = 2;
          quantization = "bitsandbytes";
          tokenizer = "google/gemma-4-E2B-it";
          limit-mm-per-prompt = lib.toJSON {
            image = 1;
            audio = 0;
            video = 0;
          };
        };
      };
    };
  };
}
