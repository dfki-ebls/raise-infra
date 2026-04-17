{ lib, config, ... }:
let
  commonArgs = {
    enable-auto-tool-choice = true;
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
      "gemma4-31b" = {
        enable = true;
        model = "RedHatAI/gemma-4-31B-it-NVFP4";
        tag = "gemma4-cu130";
        port = 18001;
        extraArgs = commonArgs // {
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
        enable = false;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        # https://huggingface.co/RedHatAI/Qwen3.6-35B-A3B-NVFP4/discussions/1
        tag = "v0.19.0-cu130";
        port = 18002;
        environment.VLLM_FLASHINFER_MOE_BACKEND = "throughput";
        # GDN/Mamba cache align mode requires block_size (2096) <= max-num-batched-tokens.
        # https://huggingface.co/Qwen/Qwen3.5-35B-A3B-GPTQ-Int4/discussions/3
        extraArgs = commonArgs // {
          enable-prefix-caching = true;
          gpu-memory-utilization = 0.7;
          max-model-len = 32 * 1024;
          max-num-batched-tokens = 2096;
          max-num-seqs = 4;
          reasoning-parser = "qwen3";
          tool-call-parser = "qwen3_coder";
        };
      };
      "qwen3.5-0.8b" = {
        enable = true;
        model = "Qwen/Qwen3.5-0.8B";
        tag = "v0.19.0-cu130";
        port = 18003;
        extraArgs = commonArgs // {
          enable-prefix-caching = false;
          gpu-memory-utilization = 0.15;
          max-model-len = 4 * 1024;
          max-num-seqs = 4;
          quantization = "fp8";
          reasoning-parser = "qwen3";
          tool-call-parser = "qwen3_coder";
        };
      };
    };
  };
}
