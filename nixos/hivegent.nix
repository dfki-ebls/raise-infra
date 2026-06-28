{
  config,
  caddyHelpers,
  ...
}:
let
  caddySubHost = caddyHelpers.mkSubHost "hivegent";
  rauthyIssuer = config.custom.rauthy.issuer;
  environmentFile = "/etc/hivegent/hivegent.env";
in
{
  services.hivegent = {
    enable = true;

    postgresql.createLocally = true;

    # Runtime secrets stay outside the Nix store.
    inherit environmentFile;

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
        model = "qwen3.6-27b";
        aux_model = "qwen3.5-0.8b";
        base_url = "http://${config.services.llmhop.settings.listen}/v1";
      };

      network = {
        websearch_language = "de";
        # Advertised in the web tools' User-Agent for traffic questions.
        contact_email = config.custom.admin.mail;
      };

      mcp = {
        enable = false;
        client_id = "hivegent-mcp";
        base_url = "${caddySubHost}/mcp";
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

  # Bootstrap only the public SPA client.
  custom.rauthy.bootstrap.clients = [
    {
      id = "hivegent-spa";
      name = "Hivegent";
      secret = null;
      client_uri = caddySubHost;
      contacts = [ config.custom.admin.mail ];
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

  # Provision the operator-managed secrets env file empty (0600, root) on
  # activation so the unit's `EnvironmentFile` does not block startup before
  # secrets are provisioned via:
  #   printf 'HIVEGENT_MCP__CLIENT_SECRET=%s\n' '<secret>' > /etc/hivegent/hivegent.env
  #   systemctl restart hivegent
  systemd.tmpfiles.rules = [ "f ${environmentFile} 0600 root root -" ];

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
}
