{
  pkgs,
  inputs,
  config,
  caddyHelpers,
  ...
}:
let
  cfg = config.custom.hivegent;
  caddySubHost = caddyHelpers.mkSubHost "hivegent";

  hivegentPackages = inputs.hivegent.packages.${pkgs.stdenv.system};

  # Rauthy's OIDC issuer is `<scheme>://<pub_url>/auth/v1/` — the
  # `/auth/v1` path is a fixed mount and rauthy emits the issuer with
  # the trailing slash in the `iss` claim, so the value here has to
  # match exactly or JWT iss validation fails.
  rauthyIssuer = "${caddyHelpers.mkSubHost "rauthy"}/auth/v1/";

  # The frontend bakes its env in at build time (Vite's
  # `import.meta.env.VITE_*` is statically replaced). Setting these as
  # derivation attrs is enough — `mkDerivation` propagates them as build
  # env, the same trick `dfki/ragold.nix` uses.
  #
  # `VITE_API_URL = ""` makes the bundle hit `/api/...` on the current
  # origin, which Caddy reverse-proxies to the backend on loopback —
  # avoids any cross-origin/CORS dance for the app itself.
  frontend = hivegentPackages.frontend.overrideAttrs {
    VITE_API_URL = "";
    VITE_OIDC_ISSUER_URI = rauthyIssuer;
    VITE_OIDC_CLIENT_ID = "hivegent-spa";
    VITE_OIDC_USE_MOCK = "false";
  };
in
{
  custom.hivegent = {
    enable = false;
    package = hivegentPackages.backend;
    host = "127.0.0.1";
    port = 8000;

    postgresql.createLocally = true;

    # `HIVEGENT_MCP__CLIENT_SECRET` must match the secret of the
    # `hivegent-mcp` confidential client created post-bootstrap via
    # the rauthy admin UI. The env file is root-owned, mode 600, and
    # operator-managed.
    environmentFile = "/etc/hivegent/hivegent.env";

    settings = {
      auth = {
        enable = true;
        issuer = rauthyIssuer;
      };

      # Match `nixos/llama-cpp.nix` — both models are preloaded there and
      # llama-server exposes an OpenAI-compatible endpoint on 18000.
      llm = {
        model = "qwen3.6-35b-a3b";
        aux_model = "qwen3.5-0.8b";
        base_url = "http://127.0.0.1:18000/v1";
      };

      mcp = {
        enable = false;
        client_id = "hivegent-mcp";
        # client_secret is supplied at runtime via `environmentFile`
        # (HIVEGENT_MCP__CLIENT_SECRET) so the value never lands in
        # /nix/store. The matching confidential client is created
        # operator-side via the rauthy admin UI.
        base_url = "${caddySubHost}/mcp";
      };
    };
  };

  # Bootstrap only the SPA — public PKCE, no secret. The companion
  # `hivegent-mcp` confidential client is created via the rauthy admin
  # UI so its secret never has to live in `/nix/store`.
  custom.rauthy.bootstrap.clients = [
    {
      id = "hivegent-spa";
      name = "Hivegent";
      secret = null;
      redirect_uris = [ "${caddySubHost}/" ];
      post_logout_redirect_uris = [ "${caddySubHost}/" ];
      allowed_origins = [ caddySubHost ];
      enabled = true;
      flows_enabled = [
        "authorization_code"
        "refresh_token"
      ];
      access_token_alg = "EdDSA";
      id_token_alg = "EdDSA";
      auth_code_lifetime = 60;
      access_token_lifetime = 1800;
      scopes = [
        "openid"
        "profile"
        "email"
        "groups"
      ];
      default_scopes = [
        "openid"
        "profile"
        "email"
        "groups"
      ];
      challenges = [ "S256" ];
      force_mfa = false;
    }
  ];

  systemd.services.hivegent = {
    # The backend resolves the OIDC discovery document at startup, and the
    # issuer URL routes through Caddy → rauthy — both must be reachable
    # before hivegent boots.
    after = [
      "caddy.service"
      "rauthy.service"
    ];
    requires = [
      "caddy.service"
      "rauthy.service"
    ];
  };

  services.caddy.virtualHosts.hivegent = {
    hostName = caddySubHost;
    extraConfig = ''
      ${caddyHelpers.mkWaf {
        # SPA + active chat sessions burn through the default 100/min
        # quickly (asset fetches, conversation polls, SSE reconnects).
        rateLimit = {
          requests = 600;
          window = "1m";
          cleanupInterval = "5m";
        };
      }}
      ${caddyHelpers.scannerHoneypots}
      ${caddyHelpers.securityHeaders}
      header Permissions-Policy "camera=(), microphone=(self), geolocation=()"
      encode zstd gzip

      # Defense-in-depth body cap. The `/api/*` handle below sets its
      # own 60 MB cap and needs it for document uploads; everything
      # else (SPA assets, honeypots, scanner paths, the static-file
      # catch-all) has no business accepting large bodies. A bare
      # site-wide `request_body` would not work — Caddy composes
      # `MaxBytesReader`s by MIN, so an outer 1 MB cap would override
      # the inner 60 MB on `/api/*`. The `not path /api/*` matcher
      # skips the cap for API requests so the inner one wins.
      @small_body not path /api/*
      request_body @small_body {
        max_size 1MB
      }

      # Defense-in-depth: even if the backend ever exposes FastAPI docs,
      # never let them through the edge. Wrapped in `handle` because a
      # top-level `respond` is sorted after `handle` by the Caddyfile
      # adapter and would be shadowed by the SPA catch-all below.
      @docs path /docs* /redoc* /openapi.json
      handle @docs {
        respond 404
      }

      handle /api/* {
        request_body {
          max_size 60MB
        }
        # API responses are JSON / binary and must never be rendered as
        # HTML by a browser tab that lands on the URL directly. Tighten
        # CSP for this path; the shared site CSP (frame-ancestors only)
        # stays for the SPA.
        header Content-Security-Policy "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
        reverse_proxy ${cfg.host}:${toString cfg.port} {
          # SSE: document conversion stage events and conversation
          # streaming need unbuffered forwarding.
          flush_interval -1
          # Passive upstream health check — Caddy stops sending traffic
          # if the backend's `/api/health` starts failing.
          health_uri      /api/health
          health_interval 10s
          health_timeout  3s
        }
      }

      ${
        if cfg.settings.mcp.enable or false then
          ''
            handle /mcp* {
              reverse_proxy ${cfg.host}:${toString cfg.port} {
                flush_interval -1
              }
            }
          ''
        else
          ''
            # MCP is opt-in: refuse at the edge when the backend has it
            # disabled so probes don't reach the upstream at all.
            @mcp path /mcp /mcp/*
            handle @mcp {
              respond 404
            }
          ''
      }

      handle {
        root * ${frontend}

        @immutable path /assets/*
        header @immutable Cache-Control "public, max-age=31536000, immutable"

        @html not path /assets/*
        header @html Cache-Control "no-store"

        header {
          -ETag
          -Last-Modified
        }

        try_files {path} /index.html
        file_server
      }
    '';
  };
}
