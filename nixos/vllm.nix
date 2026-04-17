{ lib, config, ... }:
let
  commonArgs = {
    async-scheduling = true;
    kv-cache-dtype = "fp8";
    limit-mm-per-prompt = lib.toJSON {
      image = 1;
      audio = 0;
      video = 0;
    };
  };
in
lib.mkIf config.custom.enableNvidia {
  custom.vllm = {
    enable = true;
    environmentFile = "/etc/vllm/vllm.env";
    # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
    models = {
      # https://docs.vllm.ai/projects/recipes/en/latest/Google/Gemma4.html
      "gemma4-26b" = {
        enable = false;
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        tag = "gemma4-cu130";
        port = 18001;
        extraArgs = commonArgs // {
          enable-auto-tool-choice = true;
          enable-prefix-caching = true;
          gpu-memory-utilization = 0.7;
          max-model-len = 16 * 1024;
          max-num-seqs = 4;
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          chat-template = "/vllm-workspace/examples/tool_chat_template_gemma4.jinja";
          default-chat-template-kwargs = lib.toJSON {
            enable_thinking = true;
          };
        };
      };
      # https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3.5.html
      "qwen3.6-35b" = {
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        tag = "qwen3_5-cu130";
        port = 18002;
        extraArgs = commonArgs // {
          enable-auto-tool-choice = true;
          enable-prefix-caching = true;
          gpu-memory-utilization = 0.7;
          max-model-len = 32 * 1024;
          max-num-seqs = 4;
          moe-backend = "flashinfer_cutlass";
          reasoning-parser = "qwen3";
          tool-call-parser = "qwen3_coder";
        };
      };
      "qwen3.5-0.8b" = {
        model = "Qwen/Qwen3.5-0.8B";
        tag = "qwen3_5-cu130";
        port = 18003;
        extraArgs = commonArgs // {
          enable-prefix-caching = false;
          gpu-memory-utilization = 0.1;
          max-model-len = 4 * 1024;
          max-num-seqs = 4;
          quantization = "bitsandbytes";
          reasoning-parser = "qwen3";
        };
      };
    };
  };
}
