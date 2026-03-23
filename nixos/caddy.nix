{
  pkgs,
  config,
  lib,
  ...
}:
let
  mkHost = domain: if config.custom.enableCertificates then domain else "http://${domain}";
  mkSubHost = prefix: mkHost "${prefix}.${config.custom.rootDomain}";
in
{
  _module.args.caddyHelpers = { inherit mkHost mkSubHost; };

  services.caddy = {
    enable = true;
    globalConfig = ''
      admin off
      persist_config off
      email ${config.custom.admin.mail}
    '';
    enableReload = false; # requires admin api
    virtualHosts = {
      dex = lib.mkIf config.services.dex.enable {
        hostName = mkSubHost "dex";
        extraConfig = ''
          reverse_proxy ${config.services.dex.settings.web.http}
        '';
      };
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
