{ lib, config, ... }:
{
  services.llmhop = {
    enable = config.custom.vllm.enable;
    settings = {
      listen = "127.0.0.1:8080";
      # authTokens = [ "\${file:auth_token}" ];
      models = lib.mapAttrs (_: model: {
        url = "http://127.0.0.1:${toString model.port}";
      }) (lib.filterAttrs (_: model: model.enable) config.custom.vllm.models);
    };
  };

  # systemd.services.llmhop.serviceConfig = lib.mkIf config.services.llmhop.enable {
  #   LoadCredential = [ "auth_token:/etc/llmhop/auth-token" ];
  # };
}
