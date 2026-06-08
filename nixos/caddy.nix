{
  pkgs,
  config,
  lib,
  ...
}:
let
  mkHost = domain: "${if config.custom.enableCertificates then "https" else "http"}://${domain}";
  mkSubHost = prefix: mkHost "${prefix}.${config.custom.rootDomain}";

  # Baseline response headers for public vhosts. Framing is denied by default,
  # and vhosts can opt into the specific ancestors required by their flows.
  # Browsers enforce every CSP header and apply the intersection, so the frame
  # policy must be emitted once here rather than overridden by a later header.
  securityHeaders =
    {
      frameAncestors ? [ "none" ],
    }:
    let
      formatFrameAncestor =
        source:
        if lib.elem source [ "none" "self" ] then
          "'${source}'"
        else
          source;
      xFrameOptions =
        if frameAncestors == [ "none" ] then
          "DENY"
        else if frameAncestors == [ "self" ] then
          "SAMEORIGIN"
        else
          "-X-Frame-Options";
    in
    ''
      header {
        X-Content-Type-Options nosniff
        ${if xFrameOptions == "-X-Frame-Options" then xFrameOptions else "X-Frame-Options ${xFrameOptions}"}
        Referrer-Policy strict-origin-when-cross-origin
        Content-Security-Policy "frame-ancestors ${lib.concatStringsSep " " (map formatFrameAncestor frameAncestors)}"
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
