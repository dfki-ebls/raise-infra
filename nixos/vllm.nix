{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
let
  imgSize = 1024;

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
    enable = false;
    uid = 503;
    subUidStart = 300000;
    # https://hub.docker.com/r/vllm/vllm-openai/tags
    # https://github.com/vllm-project/vllm/releases/latest
    tag = "v0.22.1";
    environmentFile = "/etc/vllm/vllm.env";

    modelSettings = {
      async-scheduling = true;
      enable-auto-tool-choice = true;
      enable-prefix-caching = true;
      gpu-memory-utilization = 0.9;
      kv-cache-dtype = "fp8";
      max-model-len = "128K";
      max-num-seqs = 2;
      default-chat-template-kwargs = lib.toJSON {
        enable_thinking = true;
      };
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
        enable = false;
        model = "google/gemma-4-31B-it-qat-w4a16-ct";
        port = 18201;
        settings = gemmaSettings;
      };
      "gemma4-26b-a4b" = {
        enable = false;
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        port = 18202;
        settings = gemmaSettings;
      };
      "qwen3.6-35b-a3b" = {
        enable = false;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        port = 18205;
        settings = qwenSettings // {
          # Keep batched tokens above the Mamba page size.
          max-num-batched-tokens = 4 * 1024;
          moe-backend = "flashinfer_cutlass";
          speculative-config = lib.toJSON {
            method = "mtp";
            num_speculative_tokens = 3;
          };
        };
      };
      "qwen3.6-27b" = {
        enable = false;
        model = "unsloth/Qwen3.6-27B-NVFP4";
        port = 18206;
        settings = qwenSettings // {
          speculative-config = lib.toJSON {
            method = "mtp";
            num_speculative_tokens = 3;
          };
        };
      };
    };
  };
}
