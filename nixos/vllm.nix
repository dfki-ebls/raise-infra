{ lib, config, ... }:
lib.mkIf config.custom.enableNvidia {
  custom.vllm = {
    enable = true;
    environmentFile = "/etc/vllm/vllm.env";
    models = {
      # https://docs.vllm.ai/projects/recipes/en/latest/Google/Gemma4.html
      # https://docs.vllm.ai/en/latest/configuration/conserving_memory/
      "gemma4-31b" = {
        model = "RedHatAI/gemma-4-26B-A4B-it-NVFP4";
        tag = "gemma4-cu130";
        port = 18001;
        extraArgs = {
          async-scheduling = true;
          enable-auto-tool-choice = true;
          enable-prefix-caching = true;
          gpu-memory-utilization = 0.9;
          kv-cache-dtype = "fp8";
          max-model-len = 16 * 1024;
          max-num-seqs = 2;
          reasoning-parser = "gemma4";
          tool-call-parser = "gemma4";
          chat-template = "/vllm-workspace/examples/tool_chat_template_gemma4.jinja";
          default-chat-template-kwargs = lib.toJSON {
            enable_thinking = true;
          };
          limit-mm-per-prompt = lib.toJSON {
            image = 2;
            audio = 0;
            video = 0;
          };
        };
      };
    };
  };
}
