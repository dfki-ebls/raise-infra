{ config, ... }:
let
  inherit (config.virtualisation) quadlet;
in
{
  virtualisation.quadlet.containers.openserp = {
    enable = false;
    containerConfig = {
      Image = "docker.io/karust/openserp:0.8.12";
      AutoUpdate = "registry";
      Exec = "serve -l";
      Environment = {
        OPENSERP_SERVER_HOST = "0.0.0.0";
        OPENSERP_SERVER_PORT = "7000";
        OPENSERP_BAIDU_RATE_REQUESTS = "6";
        OPENSERP_BAIDU_RATE_BURST = "2";
      };
      Network = quadlet.networks.external.ref;
      PublishPort = [ "7000:7000" ];
      RunInit = true;
      ShmSize = "2g";
    };
  };
}
