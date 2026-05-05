{ config, lib, ... }:
{
  virtualisation.vmVariant = {
    custom = {
      rootDomain = "localhost";
      enableWaf = false;
      enableNvidia = false;
      enableCertificates = false;
      hivegent.enable = lib.mkForce true;
    };
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

    users.users.${config.custom.admin.login}.password = "";
    security.sudo-rs.wheelNeedsPassword = false;
  };
}
