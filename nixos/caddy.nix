{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (config.virtualisation) quadlet;
  mkHost = domain: if config.custom.enableCertificates then domain else "http://${domain}";
  mkSubHost = prefix: mkHost "${prefix}.${config.custom.rootDomain}";

  website = inputs.website.packages.${pkgs.stdenv.system}.default;

  ragold = inputs.ragold.packages.${pkgs.stdenv.system}.default.overrideAttrs (prevAttrs: {
    VITE_CONTACT_INFO = "Mirko Lenz <mirko.lenz@dfki.de>";
  });
in
{
  assertions = [
    {
      assertion = !(config.services.caddy.enable && quadlet.containers.caddy.enable);
      message = "Only one of services.caddy.enable and virtualisation.quadlet.containers.caddy.enable can be set.";
    }
  ];

  services.caddy = {
    enable = true;
    globalConfig = ''
      admin off
      persist_config off
      email mirko.lenz@dfki.de
    '';
    enableReload = false; # requires admin api
    virtualHosts = {
      websiteAlias = lib.mkIf (config.custom.rootDomain == "raise.dfki.dev") {
        hostName = mkHost "raise.dfki.dev";
        extraConfig = "redir https://raise.dfki.de{uri}";
      };
      website = {
        # In production, the website is served at raise.dfki.de (not raise.dfki.dev).
        # Locally (rootDomain = "localhost"), the website is served at localhost.
        hostName = mkHost (
          if config.custom.rootDomain == "raise.dfki.dev" then "raise.dfki.de" else config.custom.rootDomain
        );
        extraConfig = ''
          root * ${website}
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
      dex = lib.mkIf config.services.dex.enable {
        hostName = mkSubHost "dex";
        extraConfig = ''
          reverse_proxy ${config.services.dex.settings.web.http}
        '';
      };
      authelia = lib.mkIf config.services.authelia.instances.main.enable {
        hostName = mkSubHost "authelia";
        extraConfig = ''
          reverse_proxy http://127.0.0.1:9091
        '';
      };
      ragold = {
        hostName = mkSubHost "ragold";
        extraConfig = ''
          root * ${ragold}
          encode zstd gzip

          @immutable path /assets/*
          header @immutable Cache-Control "public, max-age=31536000, immutable"

          @html not path /assets/*
          header @html Cache-Control "no-store"

          header {
            -ETag
            -Last-Modified
          }

          try_files {path} /index.html
          file_server
        '';
      };
    };
  };
  systemd.tmpfiles.settings.caddy = lib.mkIf quadlet.containers.caddy.enable {
    "${config.services.caddy.dataDir}/data".d = {
      user = "50000";
      group = "50000";
    };
    "${config.services.caddy.dataDir}/config".d = {
      user = "50000";
      group = "50000";
    };
  };
  virtualisation.quadlet.containers.caddy = {
    enable = false;
    imageStream = pkgs.caddy-docker;
    containerConfig = {
      Volume = [
        "${config.services.caddy.configFile}:/etc/caddy/Caddyfile:ro"
        "${config.services.caddy.dataDir}/data:/data"
        "${config.services.caddy.dataDir}/config:/config"
      ];
      Network = [
        quadlet.networks.external.ref
        quadlet.networks.internal.ref
      ];
      PublishPort = [
        "80:80"
        "443:443"
        "443:443/udp"
      ];
      AddCapability = [ "NET_BIND_SERVICE" ];
      SubUIDMap = "quadlet";
      SubGIDMap = "quadlet";
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [
      443
    ];
  };
}
