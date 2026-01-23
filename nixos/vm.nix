{ ... }:
{
  virtualisation.vmVariant = {
    custom.rootDomain = "localhost";
    custom.enableCertificates = false;
    services.caddy.globalConfig = ''
      auto_https off
    '';
    virtualisation = {
      graphics = true;
      forwardPorts = [
        {
          from = "host";
          host.port = 2222;
          guest.port = 22;
        }
        {
          from = "host";
          host.port = 80;
          guest.port = 80;
        }
      ];
    };

    users.users.mlenz.password = "";
    security.sudo-rs.wheelNeedsPassword = false;
  };
}
