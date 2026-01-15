{ ... }:
{
  virtualisation.vmVariant = {
    virtualisation = {
      graphics = true;
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
      ];
    };

    users.users.mlenz.password = "";
  };
}
