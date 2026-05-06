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

      # Same-origin requests don't need this, but the OIDC token endpoint
      # is on a different subdomain — list the SPA origin so any direct
      # cross-origin call (e.g. tooling, debugging) still works.
      cors_origins = [ caddySubHost ];

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
      encode zstd gzip

      handle /api/* {
        reverse_proxy ${cfg.host}:${toString cfg.port}
      }

      handle /mcp* {
        reverse_proxy ${cfg.host}:${toString cfg.port} {
          flush_interval -1
        }
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
