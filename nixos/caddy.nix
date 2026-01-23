{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (config.virtualisation) quadlet;

  ragold = inputs.ragold.packages.${pkgs.stdenv.system}.app;

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
          respond "Hello World!"
        '';
      };
      dex = {
        hostName = "${prefix}auth.${config.custom.rootDomain}";
        extraConfig = ''
          reverse_proxy ${config.services.dex.settings.web.http}
        '';
      };
      ragold = {
        hostName = "${prefix}ragold.${config.custom.rootDomain}";
        extraConfig = ''
          root * ${ragold}
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
