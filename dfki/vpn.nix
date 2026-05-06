{
  config,
  lib,
  caddyHelpers,
  ...
}:
{
  services.caddy.virtualHosts.rauthy = lib.mkIf config.custom.rauthy.enable {
    extraConfig = lib.mkBefore (caddyHelpers.mkAllowedSources [ "136.199.45.0/24" ]);
  };
  services.caddy.virtualHosts.hivegent = lib.mkIf config.custom.hivegent.enable {
    extraConfig = lib.mkBefore (caddyHelpers.mkAllowedSources [ "136.199.45.0/24" ]);
  };
}
