{ lib, ... }:
let
  # Server-local `client_ip` allowlist for the internal services, resolved when
  # Caddy adapts its config at startup. The directory lives only on the server,
  # so the allowlist changes with a `systemctl restart caddy`, no rebuild.
  # Loopback stays allowed for local clients such as Hivegent's OIDC discovery,
  # and keeps the matcher non-empty, since an import glob matching no files is
  # a no-op, so everyone else is denied if the drop-ins are missing.
  inject.extraConfig = lib.mkBefore ''
    @vpn_blocked not {
      client_ip 127.0.0.0/8 ::1
      import /etc/caddy/vpn.d/*.caddy
    }
    handle @vpn_blocked {
      respond "Access denied: Your IP is not allowed to access this resource." 403
    }
  '';
in
{
  services.caddy.virtualHosts = {
    rauthy = inject;
    hivegent = inject;
  };
}
