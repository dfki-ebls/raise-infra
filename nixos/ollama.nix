{
  lib,
  config,
  pkgs,
  ...
}:
lib.mkIf config.custom.enableNvidia {
  systemd.services.ollama-model-warmup = {
    description = "Load ollama models into memory";
    wantedBy = [ "multi-user.target" ];
    after = [ "ollama-model-loader.service" ];
    bindsTo = [ "ollama.service" ];
    requires = [ "ollama-model-loader.service" ];
    inherit (config.systemd.services.ollama) environment;
    serviceConfig = {
      Type = "oneshot";
      DynamicUser = true;
    };
    script = ''
      ${lib.concatMapStringsSep "\n" (model: ''
        echo "Loading ${model} into memory..."
        ${lib.getExe config.services.ollama.package} run ${lib.escapeShellArg model} ""
      '') config.services.ollama.loadModels}

      echo "Verifying all models are loaded..."
      loaded=$(${lib.getExe config.services.ollama.package} ps | tail -n +2 | wc -l)
      expected=${toString (lib.length config.services.ollama.loadModels)}
      if [ "$loaded" -ne "$expected" ]; then
        echo "ERROR: expected $expected models loaded, got $loaded. Check VRAM capacity." >&2
        exit 1
      fi
      echo "All $expected models loaded successfully."
    '';
  };

  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    openFirewall = false;
    syncModels = true;
    loadModels = [
      # "gpt-oss:20b"
      "qwen3.5:0.8b"
      # "qwen3.5:2b"
      # "qwen3.5:4b"
      # "qwen3.5:9b"
      "qwen3.5:27b"
      # "qwen3.5:35b"
    ];
    # ollama serve --help
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = toString (32 * 1024);
      OLLAMA_FLASH_ATTENTION = "1";
      OLLAMA_KEEP_ALIVE = "-1";
      OLLAMA_KV_CACHE_TYPE = "q4_0";
      OLLAMA_MAX_LOADED_MODELS = "8";
      OLLAMA_NO_CLOUD = "1";
      OLLAMA_NUM_PARALLEL = "1";
    };
  };
}
