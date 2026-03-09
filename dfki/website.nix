{
  config,
  pkgs,
  lib,
  inputs,
  caddyHelpers,
  ...
}:
{
  services.caddy.virtualHosts = {
    websiteAlias = lib.mkIf (config.custom.rootDomain == "raise.dfki.dev") {
      hostName = caddyHelpers.mkHost "raise.dfki.dev";
      extraConfig = "redir https://raise.dfki.de{uri}";
    };
    website = {
      # In production, the website is served at raise.dfki.de (not raise.dfki.dev).
      # Locally (rootDomain = "localhost"), the website is served at localhost.
      hostName = caddyHelpers.mkHost (
        if config.custom.rootDomain == "raise.dfki.dev" then "raise.dfki.de" else config.custom.rootDomain
      );
      extraConfig = ''
        root * ${inputs.website.packages.${pkgs.stdenv.system}.default}
        encode zstd gzip

        @immutable path /assets/*
        header @immutable Cache-Control "public, max-age=31536000, immutable"

        @html not path /assets/*
        header @html Cache-Control "no-store"

        header {
          -ETag
          -Last-Modified
        }

        file_server

        handle_errors {
          @404 expression {http.error.status_code} == 404
          rewrite @404 /404.html
          file_server
        }
      '';
    };
  };
}
