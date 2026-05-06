{ config, lib, ... }:
{
  virtualisation.vmVariant = {
    disabledModules = [ ../dfki/vpn.nix ];
    custom = {
      rootDomain = "localhost";
      enableWaf = false;
      enableNvidia = false;
      enableCertificates = false;
      hivegent = {
        enable = lib.mkForce true;
        # MCP SDK's `validate_issuer_url` only accepts HTTP for `localhost`
        # or `127.0.0.1`; the default `hivegent.localhost` fails that check.
        settings.mcp.base_url = lib.mkForce "http://localhost/mcp";
      };
      rauthy.enable = lib.mkForce true;
    };
    services.caddy.globalConfig = ''
      auto_https off
    '';
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
