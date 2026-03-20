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
      "gpt-oss:20b"
      "qwen3.5:35b"
    ];
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "16384";
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KEEP_ALIVE = "60m";
      OLLAMA_KV_CACHE_TYPE = "q8_0";
      OLLAMA_MAX_LOADED_MODELS = "1";
      OLLAMA_MAX_QUEUE = "64";
      OLLAMA_NUM_PARALLEL = "1";
    };
  };
}
