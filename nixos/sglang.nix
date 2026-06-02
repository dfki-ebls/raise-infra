{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
let
  imgSize = 1024;

  instantSettings = {
    mem-fraction-static = 0.1;
    context-length = 2 * 1024;
    chunked-prefill-size = 512;
    quantization = "fp8";
    disable-cuda-graph = true;
    disable-radix-cache = true;
  };

  thinkingSettings = {
    mem-fraction-static = 0.7;
    context-length = 16 * 1024;
    chunked-prefill-size = 1024;
  };

  # https://docs.sglang.io/cookbook/autoregressive/Google/Gemma4
  gemmaSettings = {
    reasoning-parser = "gemma4";
    tool-call-parser = "gemma4";
    mm-process-config = lib.toJSON {
      image.max_soft_tokens = 1120;
    };
  };

  # https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.6
  qwenSettings = {
    reasoning-parser = "qwen3";
    tool-call-parser = "qwen3_coder";
    # SM120 needs the Triton multimodal attention backend.
    mm-attention-backend = "triton_attn";
    mm-process-config = lib.toJSON {
      image.size = {
        longest_edge = imgSize * imgSize;
        shortest_edge = 4 * 1024;
      };
    };
  };
in
lib.mkIf config.custom.enableNvidia {
  services.llmhop.sglang = {
    enable = false;
    uid = 504;
    subUidStart = 400000;
    environmentFile = "/etc/sglang/sglang.env";
    # https://hub.docker.com/r/lmsysorg/sglang/tags
    # https://github.com/sgl-project/sglang/releases/latest
    tag = "v0.5.10.post1-cu130";

    gateway = {
      enable = false;
      port = 18300;
      # https://hub.docker.com/r/lmsysorg/sgl-model-gateway/tags
      tag = "v0.3.2";
      # https://docs.sglang.io/docs/advanced_features/sgl_model_gateway
      settings = rec {
        policy = "cache_aware";
        max-concurrent-requests = 8; # 2-4x worker count
        queue-size = 2 * max-concurrent-requests;
        request-timeout-secs = 120;
      };
    };

    modelSettings = {
      max-running-requests = 2;
      cuda-graph-max-bs = 2;
      # This works with uncalibrated checkpoints.
      kv-cache-dtype = "fp8_e5m2";
      # Triton is the SM120-compatible backend here.
      attention-backend = "triton";
      limit-mm-data-per-request = lib.toJSON {
        image = 1;
        video = 0;
        audio = 0;
      };
    };

    # https://docs.sglang.io/docs/advanced_features/server_arguments
    # https://docs.sglang.io/cookbook/
    models = {
      "gemma4-31b" = {
        enable = false;
        tag = "cu13-gemma4";
        model = "RedHatAI/gemma-4-31B-it-NVFP4";
        port = 18301;
        settings = thinkingSettings // gemmaSettings;
      };
      "gemma4-26b" = {
        enable = false;
        tag = "cu13-gemma4";
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        port = 18302;
        settings = thinkingSettings // gemmaSettings;
      };
      "gemma4-2b" = {
        enable = false;
        tag = "cu13-gemma4";
        model = "google/gemma-4-E2B-it";
        port = 18303;
        settings = instantSettings // gemmaSettings;
      };
      "qwen3.6-35b" = {
        enable = false;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        port = 18305;
        settings = thinkingSettings // qwenSettings;
      };
      "qwen3.5-0.8b" = {
        enable = false;
        model = "Qwen/Qwen3.5-0.8B";
        port = 18306;
        settings = instantSettings // qwenSettings;
      };
    };
  };
}
