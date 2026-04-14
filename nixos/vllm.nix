{ lib, ... }:
let
  mkArgs = lib.cli.toCommandLineShellGNU { };

  # https://docs.vllm.ai/projects/recipes/en/latest/Google/Gemma4.html
  gemmaArgs = {
    async-scheduling = true;
    gpu-memory-utilization = 0.9;
    kv-cache-dtype = "fp8";
    max-model-len = 65536;
    reasoning-parser = "gemma4";
    tool-call-parser = "gemma4";
    enable-auto-tool-choice = true;
    limit-mm-per-prompt = "image=4,audio=0";
    tensor-parallel-size = 8;
    chat-template = "examples/tool_chat_template_gemma4.jinja";
    default-chat-template-kwargs = lib.toJSON {
      enable_thinking = true;
    };
  };
in
{
  custom.vllm = {
    enable = false;
    models = {
      "gemma4-31b" = {
        model = "nvidia/Gemma-4-31B-IT-NVFP4";
        port = 18001;
        extraArgs = mkArgs (
          gemmaArgs
          // {
            quantization = "modelopt";
          }
        );
      };
      "gemma4-e2b" = {
        model = "google/gemma-4-E2B-it";
        port = 18002;
        extraArgs = mkArgs gemmaArgs;
      };
    };
  };
}
