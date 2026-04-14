{ lib, config, ... }:
{
  services.llmhop = {
    enable = config.custom.vllm.enable;
    settings = {
      listen = "127.0.0.1:8080";
      models = lib.mapAttrs (_: m: {
        url = "http://127.0.0.1:${toString m.port}";
      }) config.custom.vllm.models;
    };
  };
}
