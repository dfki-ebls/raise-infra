{ ... }:
{
  services.llmhop = {
    enable = true;
    # Unix sockets only, one per client, see README.
    port = null;
    listen.hivegent.socketGroup = "hivegent";
  };
}
