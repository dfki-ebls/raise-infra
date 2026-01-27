{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (config.virtualisation) quadlet;
  prefix = if config.custom.enableCertificates then "" else "http://";
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
      email mirko.lenz@dfki.de
    '';
    # requires admin api
    enableReload = false;
    virtualHosts = {
      "${prefix}raise.dfki.de".extraConfig = "redir https://raise.dfki.dev{uri}";
      default = {
        hostName = "${prefix}${config.custom.rootDomain}";
        extraConfig = ''
          root * ${inputs.website.packages.${pkgs.stdenv.system}.default}
          encode gzip
          try_files {path} /404/
          file_server
        '';
      };
      dex = lib.mkIf config.services.dex.enable {
        hostName = "${prefix}dex.${config.custom.rootDomain}";
        extraConfig = ''
          reverse_proxy ${config.services.dex.settings.web.http}
        '';
      };
      authelia = lib.mkIf config.services.authelia.instances.main.enable {
        hostName = "${prefix}authelia.${config.custom.rootDomain}";
        extraConfig = ''
          reverse_proxy http://127.0.0.1:9091
        '';
      };
      ragold = {
        hostName = "${prefix}ragold.${config.custom.rootDomain}";
        extraConfig = ''
          root * ${inputs.ragold.packages.${pkgs.stdenv.system}.default}
          encode gzip
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
