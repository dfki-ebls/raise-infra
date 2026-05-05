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
    VITE_OIDC_ISSUER_URI = config.services.dex.settings.issuer;
    VITE_OIDC_CLIENT_ID = "hivegent-spa";
    VITE_OIDC_USE_MOCK = "false";
  };

  mcpSecret = config.custom.dex.sharedSecrets.hivegent-mcp;
in
{
  services.dex.settings = {
    web.allowedOrigins = [ caddySubHost ];
    staticClients = [
      {
        # SPA client: oidc-spa drives a public PKCE flow with the redirect
        # landing back on the app's root URL (no callback route exists).
        id = "hivegent-spa";
        name = "Hivegent SPA";
        public = true;
        redirectURIs = [ "${caddySubHost}/" ];
      }
      {
        # Confidential client for FastMCP's `OIDCProxy` — the backend
        # validates inbound MCP tokens against dex using these credentials.
        id = "hivegent-mcp";
        name = "Hivegent MCP";
        secretEnv = mcpSecret.dexVar;
        redirectURIs = [ "${caddySubHost}/mcp" ];
      }
    ];
  };

  custom.dex.sharedSecrets.hivegent-mcp = {
    dexVar = "DEX_HIVEGENT_MCP_SECRET";
    file = "/etc/hivegent/hivegent.env";
    var = "HIVEGENT_MCP__CLIENT_SECRET";
  };

  custom.hivegent = {
    enable = false;
    package = hivegentPackages.backend;
    host = "127.0.0.1";
    port = 8000;
    environmentFile = mcpSecret.file;

    settings = {
      auth = {
        disabled = false;
        issuer = config.services.dex.settings.issuer;
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
        client_id = "hivegent-mcp";
        # client_secret is populated at runtime via `environmentFile`
        # (see `mcpSecret` above) so the value never lands in /nix/store.
        base_url = "${caddySubHost}/mcp";
      };
    };
  };

  systemd.services.hivegent = {
    after = [ "dex-generate-secrets.service" ];
    requires = [ "dex-generate-secrets.service" ];
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
