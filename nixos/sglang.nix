{ lib, config, ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
# Workstation Blackwell is SM120 (GB20x), NOT SM100 (GB100/GB200 datacenter Blackwell).
let
  imgSize = 1024;

  # Tiny "instant-reply" profile sized for a 32 GB card. CUDA graphs disabled because
  # at this scale the graph buffers cost more memory than the model itself.
  instantSettings = {
    mem-fraction-static = 0.1;
    context-length = 2 * 1024;
    chunked-prefill-size = 512;
    quantization = "fp8";
    disable-cuda-graph = true;
    # One-shot traffic; don't evict prefixes held by agentic workers.
    disable-radix-cache = true;
  };

  # Larger thinking/tool-using profile sized for a 32 GB card. HiCache (hierarchical
  # cache) is unavailable: it requires pure MHA or MLA, but Gemma4 uses sliding window
  # attention and Qwen3.6 is a mamba hybrid.
  thinkingSettings = {
    mem-fraction-static = 0.7;
    context-length = 16 * 1024;
    chunked-prefill-size = 1024;
    enable-hierarchical-cache = false;
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
    # fa3 (Hopper) and fa4 (SM100) don't apply on SM120; triton_attn is the fallback.
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
  custom.sglang = {
    enable = true;
    environmentFile = "/etc/sglang/sglang.env";
    # https://hub.docker.com/r/lmsysorg/sglang/tags
    # https://github.com/sgl-project/sglang/releases/latest
    tag = "v0.5.10.post1-cu130";

    modelSettings = {
      max-running-requests = 2;
      cuda-graph-max-bs = 2;
      # fp4_e2m1 would halve KV memory but PyTorch lacks fill_cuda for it (buffer alloc
      # crashes); fp8_e4m3 needs calibrated k_scale/v_scale, fp8_e5m2's wider exponent
      # tolerates uncalibrated checkpoints.
      kv-cache-dtype = "fp8_e5m2";
      # KV4 MHA rejects flashinfer, and trtllm_mha prefill is SM100-only (datacenter
      # Blackwell). On SM120 workstation Blackwell, triton is the remaining pick that
      # preserves radix cache for the Qwen3.6 hybrid (mamba) architecture.
      attention-backend = "triton";
      # SGLang only clamps counts, not resolution (sgl-project/sglang#9164); resolution
      # is bounded per-model via `mm-process-config`.
      limit-mm-data-per-request = lib.toJSON {
        image = 1;
        video = 0;
        audio = 0;
      };
    };

    gateway = {
      enable = true;
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

    # https://docs.sglang.io/docs/advanced_features/server_arguments
    # https://docs.sglang.io/cookbook/
    models = {
      "gemma4-31b" = {
        enable = false;
        tag = "cu13-gemma4";
        model = "RedHatAI/gemma-4-31B-it-NVFP4";
        settings = thinkingSettings // gemmaSettings;
      };
      "gemma4-26b" = {
        enable = true;
        tag = "cu13-gemma4";
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        settings = thinkingSettings // gemmaSettings;
      };
      "gemma4-2b" = {
        enable = false;
        tag = "cu13-gemma4";
        model = "google/gemma-4-E2B-it";
        settings = instantSettings // gemmaSettings;
      };
      "qwen3-6-35b" = {
        enable = false;
        model = "RedHatAI/Qwen3.6-35B-A3B-NVFP4";
        settings = thinkingSettings // qwenSettings;
      };
      "qwen3-5-0-8b" = {
        enable = true;
        model = "Qwen/Qwen3.5-0.8B";
        settings = instantSettings // qwenSettings;
      };
    };
  };
}
