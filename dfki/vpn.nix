{
  config,
  lib,
  caddyHelpers,
  ...
}:
{
  services.caddy.virtualHosts.dex = lib.mkIf config.services.dex.enable {
    extraConfig = lib.mkBefore (caddyHelpers.mkAllowedSources [ "136.199.45.0/24" ]);
  };
  services.caddy.virtualHosts.hivegent = lib.mkIf config.custom.hivegent.enable {
    extraConfig = lib.mkBefore (caddyHelpers.mkAllowedSources [ "136.199.45.0/24" ]);
  };
}
