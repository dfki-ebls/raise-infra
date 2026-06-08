{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
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
  services.llmhop.vllm = {
    enable = true;
    uid = 503;
    subUidStart = 300000;
    # https://hub.docker.com/r/vllm/vllm-openai/tags
    # https://github.com/vllm-project/vllm/releases/latest
    tag = "v0.22.1";
    environmentFile = "/etc/vllm/vllm.env";

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
        };
        audio = {
          count = 0;
        };
      };
    };

    # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
    models = {
      "gemma4-31b" = {
        enable = true;
        model = "google/gemma-4-31B-it-qat-w4a16-ct";
        port = 18201;
        settings =
          thinkingSettings
          // gemmaSettings
          // {
            speculative-config = lib.toJSON {
              model = "google/gemma-4-31B-it-assistant";
              num_speculative_tokens = 4;
            };
          };
      };
      "gemma4-26b-a4b" = {
        enable = false;
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        port = 18202;
        settings = thinkingSettings // gemmaSettings;
      };
      "gemma4-2b" = {
        enable = false;
        model = "google/gemma-4-E2B-it";
        port = 18203;
        settings = instantSettings // gemmaSettings;
      };
      "qwen3.6-35b-a3b" = {
        enable = false;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        port = 18205;
        # Keep batched tokens above the Mamba page size.
        settings =
          thinkingSettings
          // qwenSettings
          // {
            max-num-batched-tokens = 4 * 1024;
            moe-backend = "flashinfer_cutlass";
            speculative-config = lib.toJSON {
              method = "mtp";
              num_speculative_tokens = 3;
            };
          };
      };
      "qwen3.5-0.8b" = {
        enable = false;
        model = "Qwen/Qwen3.5-0.8B";
        port = 18206;
        settings = instantSettings // qwenSettings;
      };
    };
  };
}
