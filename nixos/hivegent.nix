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

  # The issuer must include Rauthy's fixed path and trailing slash.
  rauthyIssuer = "${caddyHelpers.mkSubHost "rauthy"}/auth/v1/";

  # Vite reads these variables at build time.
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

    # Runtime secrets stay outside the Nix store.
    environmentFile = "/etc/hivegent/hivegent.env";

    settings = {
      auth = {
        enable = true;
        issuer = rauthyIssuer;
      };

      llm = {
        model = "qwen3.6-35b-a3b";
        aux_model = "qwen3.5-0.8b";
        base_url = "http://127.0.0.1:18000/v1";
      };

      mcp = {
        enable = false;
        client_id = "hivegent-mcp";
        base_url = "${caddySubHost}/mcp";
      };
    };
  };

  # Bootstrap only the public SPA client.
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
    # OIDC discovery must be reachable during backend startup.
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
      ${caddyHelpers.mkGeoblock { }}
      ${caddyHelpers.scannerHoneypots}
      ${caddyHelpers.securityHeaders}
      header Permissions-Policy "camera=(), microphone=(self), geolocation=()"
      encode zstd gzip

      # Keep large uploads limited to API routes.
      @small_body not path /api/*
      request_body @small_body {
        max_size 1MB
      }

      @docs path /docs* /redoc* /openapi.json
      handle @docs {
        respond 404
      }

      handle /api/* {
        request_body {
          max_size 60MB
        }
        header Content-Security-Policy "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
        reverse_proxy ${cfg.host}:${toString cfg.port} {
          flush_interval -1
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
