{
  lib,
  caddyHelpers,
  ...
}:
{
  services.caddy.virtualHosts.rauthy = {
    extraConfig = lib.mkBefore (caddyHelpers.mkAllowedSources [ "136.199.45.0/24" ]);
  };
  services.caddy.virtualHosts.hivegent = {
    extraConfig = lib.mkBefore (caddyHelpers.mkAllowedSources [ "136.199.45.0/24" ]);
  };
}
