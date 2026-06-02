{ config, lib, ... }:
{
  virtualisation.vmVariant = {
    disabledModules = [ ../dfki/vpn.nix ];
    custom = {
      rootDomain = "localhost";
      enableGeoblocking = false;
      enableNvidia = false;
      enableCertificates = false;
      hivegent = {
        enable = lib.mkForce true;
        # The MCP SDK only accepts HTTP issuers on `localhost` or `127.0.0.1`.
        settings.mcp.base_url = lib.mkForce "http://localhost/mcp";
      };
      rauthy.enable = lib.mkForce true;
    };
    services.caddy.globalConfig = ''
      auto_https off
    '';

    # glibc needs resolved for wildcard localhost names inside the guest.
    services.resolved.enable = true;
    virtualisation = {
      graphics = false;
      cores = 8;
      memorySize = 16 * 1024;
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
