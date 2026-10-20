{
  lib,
  config,
  pkgs,
  inputs,
  caddyHelpers,
  ...
}:
let
  caddySubHost = caddyHelpers.mkSubHost "hivegent";
  hivegentUrl = caddyHelpers.mkSubUrl "hivegent";
  rauthyIssuer = config.custom.rauthy.issuer;

  # Resolved to llmhop's socket through `network.unix_sockets`.
  llmhopUrl = "http://llmhop";
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

    # patchelf 0.19 corrupts the CUDA executables bundled in the GPU wheels,
    # which this hook patches a second time (see `nixos/nvidia.nix`).
    package = inputs.hivegent.packages.${pkgs.stdenv.hostPlatform.system}.backend.override {
      autoAddDriverRunpath = pkgs.autoAddDriverRunpath.overrideAttrs (prev: {
        propagatedBuildInputs = prev.propagatedBuildInputs ++ [ pkgs.stable.patchelf ];
      });
    };

    postgresql.createLocally = true;
    searxng.createLocally = withWeb true;

    # Device placement for every torch / onnxruntime model (dense embeddings,
    # the model-based chunkers, docling) is decided centrally by the process
    # environment rather than per-library config — the backend uses `auto`
    # detection everywhere. Hide the GPU for now so the whole VRAM budget
    # stays with the llama-server; `auto` then resolves to CPU for all of
    # them. Drop this once there is GPU headroom to offload onto.
    environment.CUDA_VISIBLE_DEVICES = "";

    settings = {
      auth = {
        enable = true;
        issuer = rauthyIssuer;
        audience = [ "hivegent-*" ];
      };

      compute = {
        # 64-core host: lift the CPU-thread default for the OCR / PDF-parse
        # and (with the GPU hidden) the neural stages without oversubscribing,
        # as Tesseract's OpenMP scales sublinearly past ~16.
        num_threads = 16;
      };

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

      # Lets web_fetch open any public page the user or a search named.
      security = withWeb { web_urls.allow_hosts = [ "*" ]; };

      network = {
        # Advertised in web_fetch's User-Agent for traffic questions.
        contact_email = config.custom.admin.mail;
        unix_sockets.llmhop = config.services.llmhop.socket;
      };

      mcp = {
        enable = false;
        client_id = "hivegent-mcp";
        base_url = "${hivegentUrl}/mcp";
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
      # The SPA reads its OIDC config from the backend's `/api/config` (issuer
      # from `settings.auth.issuer` above, client id `hivegent-spa` by default),
      # so there is no per-deployment frontend build.
      # Site-wide hardening the reusable module intentionally leaves out.
      extraConfig = ''
        ${caddyHelpers.mkGeoblock { }}
        ${caddyHelpers.scannerHoneypots}
      '';
    };
  };

  custom.credstore = lib.mkMerge [
    (withTransparency {
      HIVEGENT_TRANSPARENCY__SECRET_KEY = "${openssl} rand -base64 32";
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

  # Bootstrap only the public SPA client.
  custom.rauthy.bootstrap.clients = [
    {
      id = "hivegent-spa";
      name = "Hivegent";
      secret = null;
      client_uri = hivegentUrl;
      contacts = [ config.custom.admin.mail ];
      redirect_uris = [ "${hivegentUrl}/" ];
      post_logout_redirect_uris = [ "${hivegentUrl}/" ];
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
      # Rauthy emits roles without a dedicated scope, while groups need the groups scope.
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
    # The backend fetches OIDC discovery from the Rauthy issuer during startup,
    # and that public issuer URL is served through Caddy, so order the backend
    # behind both to reach discovery on the first try. Ordering only, never
    # `requires`: Caddy restarts on every vhost change on this host (all sites
    # share one instance, and `enableReload = false` turns each change into a
    # full restart), and a requirement dependency would propagate that restart
    # into the backend, needlessly reloading its ML models. `after` carries no
    # such stop/restart propagation, and both units are independently enabled.
    after = [
      "caddy.service"
      "rauthy.service"
    ];

    # Grants the dynamic user access to llmhop's socket.
    serviceConfig.SupplementaryGroups = [ config.services.llmhop.socketGroup ];
  };
}
