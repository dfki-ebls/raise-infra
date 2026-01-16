{
  pkgs,
  config,
  lib,
  ...
}:
let
  inherit (config.virtualisation) quadlet;
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
    '';
    virtualHosts.default = {
      hostName = lib.mkDefault "raise.dfki.de";
      extraConfig = ''
        respond "Hello World!"
      '';
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
