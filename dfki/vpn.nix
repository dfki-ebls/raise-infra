{ lib, ... }:
let
  # Server-local Caddyfile drop-ins for the internal services, resolved when
  # Caddy adapts its config at startup. The directory lives only on the server,
  # so access rules such as a VPN client_ip allowlist change with a
  # `systemctl restart caddy`, no rebuild. An import glob matching no files is a
  # no-op, so the vhosts stay unrestricted in CI and on a fresh image.
  inject.extraConfig = lib.mkBefore "import /etc/caddy/vpn.d/*.caddy";
in
{
  services.caddy.virtualHosts = {
    rauthy = inject;
    hivegent = inject;
  };
}
