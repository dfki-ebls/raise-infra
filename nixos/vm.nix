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

    # macOS resolves `*.localhost` to loopback for the browser, but glibc
    # inside the guest does not by default. systemd-resolved synthesizes
    # loopback answers for the entire `localhost` zone (RFC 6761), which
    # lets hivegent reach the OIDC issuer at `rauthy.localhost` server-side.
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
