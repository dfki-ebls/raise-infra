{ ... }:

{
  virtualisation.vmVariant = {
    custom.rootDomain = "localhost";
    custom.vhostSuffix = ":80";
    services.caddy.globalConfig = ''
      auto_https off
    '';
    services.portunus.ldap.suffix = "dc=home,dc=arpa";
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
          host.port = 8888;
          guest.port = 80;
        }
      ];
    };

    users.users.mlenz.password = "";
    security.sudo-rs.wheelNeedsPassword = false;
  };
}
