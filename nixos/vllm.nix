{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
# Workstation Blackwell is SM120 (GB20x), NOT SM100 (GB100/GB200 datacenter Blackwell).
let
  imgSize = 1024;

  instantSettings = {
    gpu-memory-utilization = 0.1;
    max-model-len = "2K";
    kv-cache-memory-bytes = "512M";
    default-chat-template-kwargs = lib.toJSON {
      enable_thinking = false;
    };
  };

  thinkingSettings = {
    gpu-memory-utilization = 0.7;
    max-model-len = "16K";
    enable-auto-tool-choice = true;
    enable-prefix-caching = true;
    kv-cache-memory-bytes = "2G";
    default-chat-template-kwargs = lib.toJSON {
      enable_thinking = true;
    };
  };

  # https://docs.vllm.ai/projects/recipes/en/latest/Google/Gemma4.html
  gemmaSettings = {
    reasoning-parser = "gemma4";
    tool-call-parser = "gemma4";
    chat-template = "/vllm-workspace/examples/tool_chat_template_gemma4.jinja";
    mm-processor-kwargs = lib.toJSON {
      max_soft_tokens = 1120;
    };
  };

  # https://docs.vllm.ai/projects/recipes/en/latest/Qwen/Qwen3.5.html
  qwenSettings = {
    reasoning-parser = "qwen3";
    tool-call-parser = "qwen3_coder";
    mm-processor-kwargs = lib.toJSON {
      images_kwargs.size = {
        longest_edge = imgSize * imgSize;
        shortest_edge = 4096;
      };
    };
  };
in
lib.mkIf config.custom.enableNvidia {
  custom.vllm = {
    enable = false;
    tag = "v0.20.0-cu130";
    environmentFile = "/etc/vllm/vllm.env";
    environment = {
      VLLM_USE_V2_MODEL_RUNNER = "1";
    };
    modelSettings = {
      async-scheduling = true;
      kv-cache-dtype = "fp8";
      max-num-seqs = 2;
      limit-mm-per-prompt = lib.toJSON {
        image = {
          count = 1;
          width = imgSize;
          height = imgSize;
        };
        video = {
          count = 0;
          # num_frames = 32;
          # width = 512;
          # height = 512;
        };
        audio = {
          count = 0;
          # length = 480000; # ~30s at 16kH
        };
      };
    };
    # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
    models = {
      "gemma4-31b" = {
        enable = false;
        model = "RedHatAI/gemma-4-31B-it-NVFP4";
        port = 18001;
        settings = thinkingSettings // gemmaSettings;
      };
      "gemma4-26b" = {
        enable = true;
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        port = 18002;
        settings = thinkingSettings // gemmaSettings;
      };
      "gemma4-2b" = {
        enable = false;
        model = "google/gemma-4-E2B-it";
        port = 18003;
        settings = instantSettings // gemmaSettings;
      };
      "qwen3-6-35b" = {
        enable = false;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        port = 18005;
        # Hybrid Mamba+attention: vLLM aligns attention block size to the
        # Mamba page size (2096 tokens), which must be <= max-num-batched-tokens.
        settings =
          thinkingSettings
          // qwenSettings
          // {
            max-num-batched-tokens = 4 * 1024;
            moe-backend = "flashinfer_cutlass";
          };
      };
      "qwen3-5-0-8b" = {
        enable = true;
        model = "Qwen/Qwen3.5-0.8B";
        port = 18006;
        settings = instantSettings // qwenSettings;
      };
    };
  };
}
