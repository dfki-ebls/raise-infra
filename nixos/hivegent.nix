{
  lib,
  config,
  pkgs,
  caddyHelpers,
  ...
}:
let
  caddySubHost = caddyHelpers.mkSubHost "hivegent";
  hivegentUrl = caddyHelpers.mkSubUrl "hivegent";
  inherit (config.custom.rauthy) issuer origin;

  # Every OIDC client whose tokens the API accepts, matched exactly, since a
  # prefix would admit any client an IdP admin later names alike. The SPA one
  # is the backend's default `auth.frontend_client_id`.
  spaClient = "hivegent-spa";
  integrationClient = "hivegent-integration";

  # The module's own header block is deferred and sets `frame-ancestors` as
  # the whole policy at response time, overriding even the API's strict one.
  # A deferred header with a matcher sorts outside it and applies last.
  csp = lib.concatStringsSep "; ";
  apiCsp = "default-src 'none'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'";
  # Enforced for the SPA, closing every channel model output could exfiltrate
  # through (remote images, fetches, frames). oidc-spa reaches Rauthy for
  # discovery and tokens and restores sessions in a hidden Rauthy iframe,
  # previews are blob URLs.
  spaCsp = csp [
    "base-uri 'self'"
    "form-action 'self'"
    "frame-ancestors 'self'"
    "connect-src 'self' blob: data: ${origin}"
    "frame-src 'self' blob: ${origin}"
    "img-src 'self' blob: data:"
    "media-src 'self' blob:"
  ];
  # Report-only until verified in a browser, chiefly that `object-src` leaves
  # blob PDF previews working. KaTeX and Mermaid set inline styles, zip export
  # runs in a blob worker, and the hash is the theme script in `index.html`.
  spaStrictCsp = csp [
    spaCsp
    "default-src 'self'"
    "font-src 'self' data:"
    "object-src 'none'"
    "script-src 'self' 'sha256-fPAimwCvWk3vayb3NOchXjTKHEpKol20cA6iTqkXLvM='"
    "style-src 'self' 'unsafe-inline'"
    "worker-src 'self' blob:"
  ];
  inherit (config.services.hivegent.caddy) docsPath;

  # Resolved to llmhop's socket through `network.unix_sockets`.
  llmhopUrl = "http://llmhop";
  llmhopListener = config.services.llmhop.gateway.llmhop.listen.default;
  inherit (config.services.llmhop.vllm) detectors;
  withTransparency = lib.mkIf (detectors ? watermark);
  openssl = lib.getExe pkgs.openssl;

  # Web search through a local SearXNG and fetching of the pages it or the
  # user names, off until the shared instance should reach the web.
  withWeb = lib.mkIf false;
in
{
  services.hivegent = {
    enable = true;

    postgresql.createLocally = true;
    searxng.createLocally = withWeb true;

    # Every endpoint is local (Rauthy via split-horizon, llmhop and Postgres
    # via unix sockets), so confine the backend to loopback.
    allowedAddresses = [ ];

    # Device placement for every torch / onnxruntime model (dense embeddings,
    # the model-based chunkers, docling) is decided centrally by the process
    # environment rather than per-library config — the backend uses `auto`
    # detection everywhere. Hide the GPU for now so the whole VRAM budget
    # stays with the llama-server; `auto` then resolves to CPU for all of
    # them. Drop this together with `PrivateDevices` below once there is
    # GPU headroom to offload onto.
    environment.CUDA_VISIBLE_DEVICES = "";

    settings = {
      auth = {
        inherit issuer;
        audience = [
          spaClient
          integrationClient
        ];
      };

      # 32-core, 128 GB host shared with the LLM servers, Postgres, and Rauthy.
      compute = {
        # Each worker converts one document at a time and holds its own models
        # (about 4-6 GB on CPU), so 8 stay well within memory.
        worker_processes = 8;
        # Total budget split across the workers (3 each), since Tesseract's
        # OpenMP scales sublinearly and parallel documents beat wider OCR.
        # The rest stays with embeddings, Postgres, and the other services.
        num_threads = 24;
      };

      jobs = {
        # Enough files in flight that a single collection import fills the
        # worker pool, while the rest queue on it.
        max_concurrency = 4;
        collection_concurrency = 8;
      };

      # Short-lived pdfium paging processes, light next to the pool.
      isolation.max_workers = 4;

      conversion = {
        # The corpus is German-only; each extra OCR language widens
        # Tesseract's beam search (~25% slower with deu+eng).
        ocr.languages = [ "deu" ];
      };

      llm = {
        model = "qwen3.8-27b";
        base_url = "${llmhopUrl}/v1";
        inference_provider = "vllm";
      };

      multimodal = {
        # depends on image limit in vllm.nix
        max_images = 2;
      };

      security = {
        # No user-supplied endpoint, so neither a user LLM `base_url` nor a
        # per-request MCP server is reachable.
        user_urls.allow_hosts = [ ];
        # Lets web_fetch open any public page the user or a search named.
        web_urls = withWeb { allow_hosts = [ "*" ]; };
      };

      network = {
        # Advertised in web_fetch's User-Agent for traffic questions.
        contact_email = config.custom.admin.mail;
        unix_sockets.llmhop = llmhopListener.socket;
      };

      transparency = withTransparency {
        detector_url = "${llmhopUrl}/route/${detectors.watermark.name}/detect";
        report_issuer = hivegentUrl;
        contact_email = config.custom.admin.mail;
      };
    };

    caddy = {
      enable = true;
      hostName = caddySubHost;
      hsts = config.custom.enableCertificates;
      # The SPA reads its OIDC config from the backend's `/api/v1/config`
      # (`settings.auth` above), so there is no per-deployment frontend build.
      # Site-wide hardening the reusable module intentionally leaves out.
      extraConfig = ''
        ${caddyHelpers.mkGeoblock { }}
        ${caddyHelpers.scannerHoneypots}

        @csp_api path /api/*
        header @csp_api {
          defer
          Content-Security-Policy "${apiCsp}"
        }

        # The handbook is mdbook output with inline scripts, so it keeps the
        # module's policy.
        @csp_spa not path /api/* ${docsPath} ${docsPath}/*
        header @csp_spa {
          defer
          Content-Security-Policy "${spaCsp}"
          Content-Security-Policy-Report-Only "${spaStrictCsp}"
        }
      '';
    };
  };

  custom.credstore = lib.mkMerge [
    (withTransparency {
      "hivegent.TRANSPARENCY__SECRET_KEY" = "${openssl} rand -base64 32";
    })
    (withWeb {
      "searx.secret-key" = "${openssl} rand -hex 32";
    })
  ];

  services.searx = withWeb {
    enable = true;
    settings = {
      # Substituted by searx-init when it renders the settings.
      server.secret_key = "$SEARX_SECRET_KEY";
      # The corpus is German, so a search naming no language finds German pages.
      search.default_lang = "de";
    };
  };

  systemd.services.searx-init = withWeb {
    serviceConfig.ImportCredential = "searx.secret-key";
    script = lib.mkBefore ''
      SEARX_SECRET_KEY=$(< "$CREDENTIALS_DIRECTORY/searx.secret-key")
      export SEARX_SECRET_KEY
    '';
  };

  # Bootstrap only the SPA client, public without a secret, so Rauthy enforces
  # S256 PKCE. Rauthy emits roles without a dedicated scope, while groups need
  # the groups scope.
  custom.rauthy.bootstrap.clients = [
    rec {
      id = spaClient;
      name = "Hivegent";
      client_uri = hivegentUrl;
      contacts = [ config.custom.admin.mail ];
      redirect_uris = [ "${hivegentUrl}/" ];
      post_logout_redirect_uris = redirect_uris;
      allowed_origins = [ hivegentUrl ];
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
      default_scopes = scopes;
      force_mfa = false;
    }
  ];

  systemd.services.hivegent = {
    # Discovery from the public issuer goes through Caddy to Rauthy at startup.
    # Ordering only, since Caddy restarts on every vhost change here and a
    # requirement would restart the backend and reload its models with it.
    after = [
      "caddy.service"
      "rauthy.service"
    ];

    serviceConfig = {
      # Grants the dynamic user access to llmhop's socket.
      SupplementaryGroups = [ llmhopListener.socketGroup ];
      # The module exposes the host devices for CUDA, which is hidden above.
      PrivateDevices = lib.mkForce true;
    };
  };
}
