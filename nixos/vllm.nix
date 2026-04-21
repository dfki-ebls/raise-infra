{ lib, config, ... }:
let
  commonArgs = {
    async-scheduling = true;
    kv-cache-dtype = "fp8";
    max-num-seqs = 2;
    limit-mm-per-prompt = lib.toJSON {
      image = 1;
      audio = 0;
      video = 0;
    };
  };
  instantArgs = commonArgs // {
    default-chat-template-kwargs = lib.toJSON {
      enable_thinking = false;
    };
  };
  thinkingArgs = commonArgs // {
    enable-auto-tool-choice = true;
    enable-prefix-caching = true;
    default-chat-template-kwargs = lib.toJSON {
      enable_thinking = true;
    };
  };
in
lib.mkIf config.custom.enableNvidia {
  custom.vllm = {
    enable = true;
    tag = "v0.19.1-cu130";
    environmentFile = "/etc/vllm/vllm.env";
    # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
    models = {
      # https://docs.vllm.ai/projects/recipes/en/latest/Google/Gemma4.html
      "gemma4-31b" = {
        enable = false;
        model = "RedHatAI/gemma-4-31B-it-NVFP4";
        port = 18001;
        extraArgs = thinkingArgs // {
          gpu-memory-utilization = 0.75;
          max-model-len = 16 * 1024;
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          chat-template = "/vllm-workspace/examples/tool_chat_template_gemma4.jinja";
        };
      };
      "gemma4-26b" = {
        enable = true;
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        port = 18002;
        extraArgs = thinkingArgs // {
          gpu-memory-utilization = 0.7;
          max-model-len = 16 * 1024;
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          chat-template = "/vllm-workspace/examples/tool_chat_template_gemma4.jinja";
        };
      };
      "gemma4-2b" = {
        enable = false;
        model = "google/gemma-4-E2B-it";
        port = 18003;
        extraArgs = instantArgs // {
          gpu-memory-utilization = 0.2;
          max-model-len = 4 * 1024;
          quantization = "fp8";
        };
      };
      # https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3.5.html
      "qwen3.6-35b" = {
        enable = false;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        port = 18005;
        environment.VLLM_FLASHINFER_MOE_BACKEND = "throughput";
        # GDN/Mamba cache align mode requires block_size (2096) <= max-num-batched-tokens.
        # https://huggingface.co/Qwen/Qwen3.5-35B-A3B-GPTQ-Int4/discussions/3
        extraArgs = thinkingArgs // {
          gpu-memory-utilization = 0.75;
          max-model-len = 32 * 1024;
          max-num-batched-tokens = 2096;
          reasoning-parser = "qwen3";
          tool-call-parser = "qwen3_coder";
        };
      };
      "qwen3.5-0.8b" = {
        enable = true;
        model = "Qwen/Qwen3.5-0.8B";
        port = 18006;
        extraArgs = instantArgs // {
          gpu-memory-utilization = 0.15;
          max-model-len = 4 * 1024;
          quantization = "fp8";
        };
      };
    };
  };
}
