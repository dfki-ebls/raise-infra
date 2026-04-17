{ lib, config, ... }:
{
  services.llmhop = {
    enable = config.custom.vllm.enable;
    settings = {
      listen = "127.0.0.1:18000";
      models = lib.mapAttrs (_: model: {
        url = "http://127.0.0.1:${toString model.port}";
      }) (lib.filterAttrs (_: model: model.enable) config.custom.vllm.models);
    };
  };
}
