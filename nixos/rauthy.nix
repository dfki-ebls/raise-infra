{
  config,
  lib,
  caddyHelpers,
  ...
}:
let
  cfg = config.custom.rauthy;

  caddySubHost = caddyHelpers.mkSubHost "rauthy";
  pubUrl = "rauthy.${config.custom.rootDomain}";

  port = 8080;
in
{
  custom.rauthy = {
    enable = true;
    postgresql.createLocally = true;

    settings = {
      bootstrap = {
        # Rauthy logs the one-time password for this user on first DB init.
        admin_email = config.custom.admin.mail;
      };

      # Put the client id into the `sub` of client_credentials tokens.
      # Without it those tokens carry no `sub`, and downstream APIs that key
      # a principal on `sub` (Hivegent) reject them.
      access.client_credentials_map_sub = true;

      cluster = {
        # https://sebadob.github.io/rauthy/config/ha.html
        node_id = 1;
        nodes = [ "1 localhost:8100 localhost:8200" ];
      };

      server = {
        listen_address = "127.0.0.1";
        port_http = port;
        scheme = "http";
        pub_url = pubUrl;
        # Keep the local VM HTTP-only when certificates are disabled.
        proxy_mode = config.custom.enableCertificates;
        trusted_proxies = [ "127.0.0.1/32" ];
      };

      # Populating WebAuthn enables passkeys in Rauthy.
      webauthn = {
        rp_id = pubUrl;
        # Rauthy expects `rp_origin` to include the port.
        rp_origin = "${caddySubHost}:${if config.custom.enableCertificates then "443" else "80"}";
        rp_name = "RAISE IAM";
        # Require PIN or biometric verification for passkey MFA.
        force_uv = true;
      };

      user_registration.enable = false;

      email.rauthy_admin_email = config.custom.admin.mail;

      events.email = config.custom.admin.mail;

      suspicious_requests.log = false;
    };
  };

  services.caddy.virtualHosts.rauthy = lib.mkIf cfg.enable {
    hostName = caddySubHost;
    extraConfig = ''
      ${caddyHelpers.mkGeoblock { }}
      ${caddyHelpers.securityHeaders { }}
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };
}
