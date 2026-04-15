{ lib, ... }:
let
  mkArgs = lib.cli.toCommandLineShellGNU { };
in
{
  custom.vllm = {
    enable = true;
    models = {
      # https://docs.vllm.ai/projects/recipes/en/latest/Google/Gemma4.html
      "gemma4-31b" = {
        model = "nvidia/Gemma-4-31B-IT-NVFP4";
        port = 18001;
        extraArgs = mkArgs {
          # general gemma
          async-scheduling = true;
          enable-auto-tool-choice = true;
          enable-prefix-caching = true;
          gpu-memory-utilization = 0.9;
          kv-cache-dtype = "fp8";
          limit-mm-per-prompt = "image=2,audio=0";
          max-model-len = 16384;
          max-num-seqs = 4;
          quantization = "modelopt";
          reasoning-parser = "gemma4";
          swap-space = 4;
          tool-call-parser = "gemma4";
          chat-template = "./examples/tool_chat_template_gemma4.jinja";
          default-chat-template-kwargs = lib.toJSON {
            enable_thinking = true;
          };
        };
      };
    };
  };
}
