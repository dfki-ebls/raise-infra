{
  pkgs,
  config,
  lib,
  ...
}:
let
  mkHost = domain: "${if config.custom.enableCertificates then "https" else "http"}://${domain}";
  mkSubHost = prefix: mkHost "${prefix}.${config.custom.rootDomain}";

  # Baseline response headers for public vhosts. Same-origin framing is opt-in
  # so SPAs like Hivegent can run oidc-spa's hidden session-restoration iframe.
  # Browsers enforce every CSP header and apply the intersection, so the frame
  # policy must be emitted once here rather than overridden by a later header.
  securityHeaders =
    {
      allowSameOriginFraming ? false,
    }:
    ''
      header {
        X-Content-Type-Options nosniff
        X-Frame-Options ${if allowSameOriginFraming then "SAMEORIGIN" else "DENY"}
        Referrer-Policy strict-origin-when-cross-origin
        Content-Security-Policy "frame-ancestors ${if allowSameOriginFraming then "'self'" else "'none'"}"
        -Server
        ${lib.optionalString config.custom.enableCertificates ''
          Strict-Transport-Security "max-age=31536000; includeSubDomains"
        ''}
      }
    '';

  # Empty source lists mean no restriction.
  mkAllowedSources =
    sources:
    lib.optionalString (sources != [ ]) ''
      @blocked not client_ip ${toString sources}
      handle @blocked {
        respond "Access denied: Your IP is not allowed to access this resource." 403
      }
    '';

  mkGeoblock =
    {
      countries ? [ "DE" ],
    }:
    lib.optionalString config.custom.enableGeoblocking ''
      @geoblocked {
        not {
          maxmind_geolocation {
            db_path ${pkgs.dbip-country-lite.mmdb}
            allow_countries ${toString countries}
          }
        }
      }
      handle @geoblocked {
        respond "Access denied: Your location is not allowed to access this resource." 403
      }
    '';

  # Curated honeypot paths we never serve.
  scannerHoneypots = ''
    @scanner path /wp-admin* /wp-login* /wp-content* /xmlrpc.php /phpmyadmin* /pma* /.aws/* /.ssh/* /administrator /admin.php /shell.php
    handle @scanner {
      respond 404
    }
  '';
in
{
  _module.args.caddyHelpers = {
    inherit
      mkHost
      mkSubHost
      mkAllowedSources
      mkGeoblock
      scannerHoneypots
      securityHeaders
      ;
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy-custom;
    openFirewall = true;
    email = config.custom.admin.mail;
    enableReload = false; # requires admin api
    globalConfig = ''
      admin off
      persist_config off

      # Slow-loris limits.
      servers {
        timeouts {
          read_header 10s
          read_body   30s
          idle        2m
        }
      }
    '';
  };
}
