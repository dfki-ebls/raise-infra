{ ... }:
# Target hardware: NVIDIA RTX PRO 4500 Blackwell, 32 GB GDDR7.
# Workstation Blackwell is SM120 (GB20x), NOT SM100 (GB100/GB200 datacenter Blackwell).
{
  services.llama-cpp = {
    enable = true;
    port = 18000;
    extraFlags = [
      "--no-models-autoload"
      "--models-max"
      "10"
    ];
    # https://github.com/ggml-org/llama.cpp/blob/master/tools/server/README.md
    modelsPreset = {
      "*" = rec {
        # keep-sorted start
        cache-ram = 128 * 1024; # MiB
        cache-type-k = "q4_0";
        cache-type-v = "q4_0";
        ctx-size = 32 * 1024 * parallel;
        flash-attn = "on";
        mlock = true;
        mmap = false;
        n-gpu-layers = "all";
        parallel = 4;
        sleep-idle-seconds = -1;
        stop-timeout = 60;
        # keep-sorted end
      };
      # https://unsloth.ai/docs/models/qwen3.6
      "unsloth/Qwen3.6-35B-A3B-GGUF:UD-Q4_K_XL" = {
        # keep-sorted start
        alias = "qwen3.6-35b-a3b";
        load-on-startup = true;
        min-p = 0.0;
        presence-penalty = 1.0;
        reasoning = "on";
        repeat-penalty = 1.0;
        temperature = 1.0;
        top-k = 20;
        top-p = 0.95;
        # keep-sorted end
      };
      # https://unsloth.ai/docs/models/qwen3.5
      "unsloth/Qwen3.5-0.8B-GGUF:UD-Q4_K_XL" = {
        # keep-sorted start
        alias = "qwen3.5-0.8b";
        load-on-startup = true;
        min-p = 0.0;
        presence-penalty = 1.0;
        reasoning = "on";
        repeat-penalty = 1.0;
        temperature = 1.0;
        top-k = 20;
        top-p = 0.95;
        # keep-sorted end
      };
    };
  };
  systemd.services.llama-cpp = {
    serviceConfig.EnvironmentFile = "/etc/llama-cpp/llama-cpp.env";
  };
}
