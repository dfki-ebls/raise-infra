{ config, ... }:
let
  gateway = config.services.llmhop.gateway.llmhop;
in
{
  services.llmhop.gateway = {
    type = "llmhop";
    # Unix socket only, which members of llmhop's group can use, see README.
    llmhop.listen.default = {
      port = null;
      socketGroup = gateway.group;
    };
  };
}
