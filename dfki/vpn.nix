{
  lib,
  caddyHelpers,
  ...
}:
let
  injectVpn = {
    extraConfig = lib.mkBefore (
      caddyHelpers.mkAllowedSources [
        "136.199.45.0/24"
        "136.199.0.0/16"
      ]
    );
  };
in
{
  services.caddy.virtualHosts = {
    rauthy = injectVpn;
    hivegent = injectVpn;
  };
}
