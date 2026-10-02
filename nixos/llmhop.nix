{ config, ... }:
{
  services.llmhop = {
    enable = true;
    # Unix socket only, which members of llmhop's group can use, see README.
    port = null;
    socketGroup = config.services.llmhop.group;
  };
}
