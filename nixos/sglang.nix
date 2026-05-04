{ lib, config, ... }:
let
  imgSize = 1024;
  commonArgs = {
    max-running-requests = 2;
    cuda-graph-max-bs = 2;
    log-requests = true;
    # FP8 KV cache silently regresses accuracy when the checkpoint lacks calibrated
    # k_scale/v_scale; FP4 E2M1 auto-scales and uses half the memory.
    kv-cache-dtype = "fp4_e2m1";
    # SGLang only clamps counts, not resolution (sgl-project/sglang#9164); resolution
    # is bounded per-model via `mm-process-config`.
    limit-mm-data-per-request = lib.toJSON {
      image = 1;
      video = 0;
      audio = 0;
    };
  };

  # Tiny "instant-reply" profile sized for a 32 GB card. CUDA graphs disabled because
  # at this scale the graph buffers cost more memory than the model itself.
  instantArgs = commonArgs // {
    mem-fraction-static = 0.1;
    context-length = 2 * 1024;
    chunked-prefill-size = 512;
    quantization = "fp8";
    disable-cuda-graph = true;
  };

  # Larger thinking/tool-using profile sized for a 32 GB card. HiCache offloads
  # less-hot prefixes to host RAM, growing the effective prefix cache without
  # inflating GPU usage.
  thinkingArgs = commonArgs // {
    mem-fraction-static = 0.7;
    context-length = 16 * 1024;
    chunked-prefill-size = 1024;
    enable-hierarchical-cache = true;
  };
in
lib.mkIf config.custom.enableNvidia {
  custom.sglang = {
    enable = true;
    environmentFile = "/etc/sglang/sglang.env";
    # https://hub.docker.com/r/lmsysorg/sglang/tags
    # https://github.com/sgl-project/sglang/releases/latest
    tag = "v0.5.10.post1-cu130-runtime";

    gateway = {
      enable = true;
      # https://hub.docker.com/r/lmsysorg/sgl-model-gateway/tags
      tag = "v0.3.2";
      # https://docs.sglang.io/docs/advanced_features/sgl_model_gateway
      extraArgs = rec {
        policy = "cache_aware";
        max-concurrent-requests = 8; # 2-4x worker count
        queue-size = 2 * max-concurrent-requests;
        request-timeout-secs = 120;
      };
    };

    # https://docs.sglang.io/docs/advanced_features/server_arguments
    # https://docs.sglang.io/cookbook/
    models = {
      # https://docs.sglang.io/cookbook/autoregressive/Google/Gemma4
      "gemma4-31b" = {
        enable = false;
        model = "RedHatAI/gemma-4-31B-it-NVFP4";
        extraArgs = thinkingArgs // {
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          mm-process-config = lib.toJSON {
            image.max_soft_tokens = 1120;
          };
        };
      };
      "gemma4-26b" = {
        enable = false;
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        extraArgs = thinkingArgs // {
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          mm-process-config = lib.toJSON {
            image.max_soft_tokens = 1120;
          };
        };
      };
      "gemma4-2b" = {
        enable = false;
        model = "google/gemma-4-E2B-it";
        extraArgs = instantArgs // {
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          mm-process-config = lib.toJSON {
            image.max_soft_tokens = 1120;
          };
        };
      };
      # https://docs.sglang.io/cookbook/autoregressive/Qwen/Qwen3.6
      "qwen3-6-35b" = {
        enable = true;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        # Speculative decoding intentionally disabled: draft tree + verification buffers
        # + mamba `extra_buffer` all trade VRAM for latency, wrong tradeoff when
        # co-locating models. Concurrency 1 halves the mamba pool.
        extraArgs = thinkingArgs // {
          reasoning-parser = "qwen3";
          tool-call-parser = "qwen3_coder";
          mm-attention-backend = "fa3";
          mm-process-config = lib.toJSON {
            image.size = {
              longest_edge = imgSize * imgSize;
              shortest_edge = 4 * 1024;
            };
          };
        };
      };
      "qwen3-5-0-8b" = {
        enable = true;
        model = "Qwen/Qwen3.5-0.8B";
        extraArgs = instantArgs // {
          reasoning-parser = "qwen3";
          tool-call-parser = "qwen3_coder";
          mm-attention-backend = "fa3";
          mm-process-config = lib.toJSON {
            image.size = {
              longest_edge = imgSize * imgSize;
              shortest_edge = 4 * 1024;
            };
          };
        };
      };
    };
  };
}
