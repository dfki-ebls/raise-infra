{
  config,
  lib,
  caddyHelpers,
  ...
}:
let
  cfg = config.custom.rauthy;

  caddySubHost = caddyHelpers.mkSubHost "rauthy";
  pubUrl = "rauthy.${config.custom.rootDomain}";

  # Loopback port the rauthy HTTP listener binds to. Caddy reverse-proxies
  # `<caddySubHost>` here. Hiqlite separately listens on 8100 (Raft) and
  # 8200 (API) — both pinned to 127.0.0.1 below since this is a single-node
  # deployment.
  port = 8080;
in
{
  custom.rauthy = {
    enable = true;

    settings = {
      bootstrap = {
        # Initial admin user, created once on first DB init. With
        # `password_plain` omitted rauthy generates a random one-time
        # password and logs it to journal under
        # `rauthy_data::migration::bootstrap::rauthy_admin` — grep for
        # `First-Time setup` in `journalctl -u rauthy`. Log in once at
        # `<caddySubHost>/auth/v1/account` and rotate immediately; the
        # generated password is single-use.
        admin_email = config.custom.admin.mail;
      };

      cluster = {
        # Single-node deployment. The `nodes` list mirrors the Hiqlite
        # default — id 1 with raft on 8100 and api on 8200, both loopback.
        node_id = 1;
        nodes = [ "1 localhost:8100 localhost:8200" ];
        listen_addr_api = "127.0.0.1";
        listen_addr_raft = "127.0.0.1";
        # Single instance: block on each Raft log fsync. Loses some
        # throughput in exchange for the strongest consistency guarantee,
        # which matters here since there are no peers to recover from.
        log_sync = "immediate";
      };

      server = {
        listen_address = "127.0.0.1";
        port_http = port;
        # No TLS at the rauthy layer — Caddy terminates TLS upstream.
        scheme = "http";
        # `pub_url` is just `host[:port]`; rauthy combines it with `scheme`
        # internally to derive the OIDC issuer (`<scheme>://<pub_url>/auth/v1`).
        pub_url = pubUrl;
        # `proxy_mode = true` unconditionally forces the issuer scheme to
        # `https` (see `rauthy_config.rs`: `is_https = ... || proxy_mode`),
        # which would make the built-in `rauthy` client's redirect_uri
        # `https://...` even when Caddy is serving plain http (the local
        # VM has `enableCertificates = false` and `auto_https off`). Tie it
        # to the upstream TLS state so the local VM stays on http end-to-end.
        proxy_mode = config.custom.enableCertificates;
        # Trust only the local Caddy. `peer_ip_header_name` stays unset so
        # rauthy uses the standard `X-Forwarded-For` from Caddy. Only
        # consulted when `proxy_mode = true`.
        trusted_proxies = [ "127.0.0.1/32" ];
      };

      # Passkeys (WebAuthn) are enabled implicitly by populating this
      # section — there's no separate "passkeys.enable" toggle. With
      # `rp_id`/`rp_origin`/`rp_name` set, the rauthy account UI exposes
      # passkey enrolment + login at `<caddySubHost>/auth/v1/account`.
      webauthn = {
        # Effective domain for passkeys. Changing `rp_id` invalidates
        # every already-registered passkey, so set it once and leave it
        # alone.
        rp_id = pubUrl;
        # rauthy's reference config is explicit that `rp_origin` "must
        # ALWAYS include the port number". For TLS via Caddy that's
        # `:443`; if `enableCertificates = false` it's `:80`.
        rp_origin = "${caddySubHost}:${if config.custom.enableCertificates then "443" else "80"}";
        rp_name = "RAISE IAM";
        # Force user verification (PIN/biometric) during the WebAuthn
        # ceremony so passkeys count as a true second factor instead of
        # mere user-presence. Caveat: a few Android browser combos still
        # don't support UV cleanly — flip back to `false` if operators
        # report enrolment failures.
        force_uv = true;
      };

      # Closed deployment: no self-service registration. The bootstrap
      # admin creates additional users from the admin UI.
      user_registration.enable = false;

      email.rauthy_admin_email = config.custom.admin.mail;

      events.email = config.custom.admin.mail;

      # Suppress the "/" catch-all redirect logging — Caddy handles unknown
      # paths with the WAF anyway.
      suspicious_requests.log = false;
    };
  };

  services.caddy.virtualHosts.rauthy = lib.mkIf cfg.enable {
    hostName = caddySubHost;
    extraConfig = ''
      ${caddyHelpers.mkWaf { }}
      reverse_proxy 127.0.0.1:${toString port}
    '';
  };
}
