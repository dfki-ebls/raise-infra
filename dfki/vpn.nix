{
  lib,
  caddyHelpers,
  ...
}:
let
  injectVpn = lib.mkBefore (caddyHelpers.mkAllowedSources [ "136.199.45.0/24" ]);
in
{
  services.caddy.virtualHosts = {
    rauthy.extraConfig = injectVpn;
    hivegent.extraConfig = injectVpn;
  };
}
