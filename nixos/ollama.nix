{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf config.custom.enableNvidia {
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    openFirewall = true;
    syncModels = true;
    loadModels = [
      # "gpt-oss:20b"
      "qwen3.5:0.8b"
      # "qwen3.5:2b"
      # "qwen3.5:4b"
      "qwen3.5:9b"
      "qwen3.5:27b"
      # "qwen3.5:35b"
    ];
    # ollama serve --help
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = toString 64 * 1024;
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KEEP_ALIVE = "60m";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_MAX_LOADED_MODELS = "3";
      OLLAMA_MAX_QUEUE = "128";
      OLLAMA_NO_CLOUD = "1";
      OLLAMA_NUM_PARALLEL = "4";
    };
  };
}
