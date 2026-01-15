{ ... }:

{
  virtualisation.vmVariant = {
    _module.args.caddyHostName = "http://localhost";
    services.caddy = {
      globalConfig = ''
        auto_https off
      '';
    };
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
