{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.custom.rauthy;

  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "rauthy.toml" cfg.settings;

  opensslExe = lib.getExe' pkgs.openssl "openssl";

  # JSON files Rauthy reads from `BOOTSTRAP_DIR` on first DB init.
  # Each entry maps the on-disk filename (snake_case, fixed by rauthy)
  # to the matching option (camelCase). Empty lists are dropped so we
  # only emit the files that actually have entries.
  bootstrapData = lib.filterAttrs (_: v: v != [ ]) {
    "clients.json" = cfg.bootstrap.clients;
    "users.json" = cfg.bootstrap.users;
    "groups.json" = cfg.bootstrap.groups;
    "roles.json" = cfg.bootstrap.roles;
    "scopes.json" = cfg.bootstrap.scopes;
    "user_attributes.json" = cfg.bootstrap.userAttributes;
  };
in
{
  options.custom.rauthy = {
    enable = lib.mkEnableOption "the Rauthy OIDC identity provider";

    package = lib.mkPackageOption pkgs "rauthy" { };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          bootstrap.admin_email = "admin@example.com";
          cluster = {
            node_id = 1;
            nodes = [ "1 localhost:8100 localhost:8200" ];
          };
          server = {
            scheme = "http";
            listen_address = "127.0.0.1";
            port_http = 8080;
            pub_url = "rauthy.example.com";
            proxy_mode = true;
            trusted_proxies = [ "127.0.0.1/32" ];
          };
          webauthn = {
            rp_id = "rauthy.example.com";
            rp_origin = "https://rauthy.example.com";
            rp_name = "Example IAM";
          };
        }
      '';
      description = ''
        Rauthy TOML config rendered into the Nix store and passed via
        `rauthy serve -c <file>`. See the upstream reference config at
        <https://github.com/sebadob/rauthy/blob/main/book/src/config/config.md>
        for the full list of sections (`bootstrap`, `cluster`, `server`,
        `webauthn`, `dynamic_clients`, `email`, ...).

        Do NOT put secrets here — anything in this attrset lands in
        `/nix/store` and becomes world-readable. Use environment variables
        instead: every TOML key has a matching `overwritten by: <ENV_VAR>`
        in the reference config. Hand secrets to the unit via
        `environment`, `environmentFile`, or `sharedSecrets`.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Plain environment variables set on the unit. Useful for non-secret
        overrides of TOML values (the rauthy reference config lists the
        matching `<ENV_VAR>` for every option).
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/rauthy/extra.env";
      description = ''
        Optional `KEY=VALUE` env file forwarded via `EnvironmentFile`, useful
        for operator-managed secrets like `SMTP_PASSWORD`. Loaded *after* the
        auto-generated `/etc/rauthy/rauthy.env`, so entries here win on
        conflicts. Must be readable by `root` (systemd reads it before
        dropping to the unit's `DynamicUser`).
      '';
    };

    bootstrap =
      let
        entryType = lib.types.listOf (lib.types.attrsOf lib.types.anything);
      in
      {
        clients = lib.mkOption {
          type = entryType;
          default = [ ];
          example = lib.literalExpression ''
            [
              {
                id = "spa";
                name = "Single-Page App";
                secret = null;
                redirect_uris = [ "https://app.example.com/" ];
                allowed_origins = [ "https://app.example.com" ];
                enabled = true;
                flows_enabled = [ "authorization_code" "refresh_token" ];
                access_token_alg = "EdDSA";
                id_token_alg = "EdDSA";
                auth_code_lifetime = 60;
                access_token_lifetime = 1800;
                scopes = [ "openid" "profile" "email" "groups" ];
                default_scopes = [ "openid" "profile" "email" "groups" ];
                challenges = [ "S256" ];
                force_mfa = false;
              }
            ]
          '';
          description = ''
            OIDC clients seeded into Hiqlite on first DB init via
            `bootstrap_dir/clients.json`. `secret = null` produces a
            public PKCE client; a confidential client uses
            `secret = { Plain = "<>=64 chars>"; }` (or
            `{ Encrypted = "..."; }`). `Plain` secrets land in
            `/nix/store` — treat them as throwaway bootstrap values and
            rotate via the admin UI.
          '';
        };

        users = lib.mkOption {
          type = entryType;
          default = [ ];
          example = lib.literalExpression ''
            [
              {
                email = "admin@example.com";
                given_name = "Admin";
                family_name = "Admin";
                password = { Plain = "ChangeMe123!"; };
                roles = [ "admin" ];
                groups = [ "admin" ];
                enabled = true;
                email_verified = true;
              }
            ]
          '';
          description = ''
            Users seeded via `bootstrap_dir/users.json`. `password` is
            required; prefer `{ Argon2ID = "$argon2id$..."; }` over
            `{ Plain = "..."; }` since plain values land in `/nix/store`.
          '';
        };

        groups = lib.mkOption {
          type = entryType;
          default = [ ];
          example = lib.literalExpression ''[ { name = "admin"; } ]'';
          description = "Groups seeded via `bootstrap_dir/groups.json`.";
        };

        roles = lib.mkOption {
          type = entryType;
          default = [ ];
          description = "Roles seeded via `bootstrap_dir/roles.json`.";
        };

        scopes = lib.mkOption {
          type = entryType;
          default = [ ];
          description = "Custom OIDC scopes seeded via `bootstrap_dir/scopes.json`.";
        };

        userAttributes = lib.mkOption {
          type = entryType;
          default = [ ];
          description = "User attribute definitions seeded via `bootstrap_dir/user_attributes.json`.";
        };
      };

  };

  config = lib.mkIf cfg.enable {
    # Pre-create the secrets dir at boot. The `rauthy-generate-secrets`
    # oneshot runs under `ProtectSystem = "strict"` and bind-mounts
    # `/etc/rauthy` read-write via `ReadWritePaths`; systemd silently
    # ignores missing entries there, so without this rule `/etc` stays
    # read-only inside the namespace on first boot and the script fails
    # to create the env file.
    systemd.tmpfiles.rules = [ "d /etc/rauthy 0755 root root -" ];

    custom.rauthy.environment = {
      HQL_DATA_DIR = "/var/lib/rauthy";
    }
    # Bootstrap entries are rendered to JSON under a Nix-built dir and
    # injected via env var, which overrides any `bootstrap_dir` set in
    # the TOML config. The admin email/password and any other
    # non-secret bootstrap fields stay in `settings.bootstrap.*` (see
    # the freeform `settings` option).
    // lib.optionalAttrs (bootstrapData != { }) {
      BOOTSTRAP_DIR = toString (
        pkgs.linkFarm "rauthy-bootstrap" (
          lib.mapAttrsToList (name: value: {
            inherit name;
            path = pkgs.writeText name (builtins.toJSON value);
          }) bootstrapData
        )
      );
    };

    # The Hiqlite Raft/API tokens (`HQL_SECRET_*`) and ChaCha20Poly1305
    # encryption keys (`ENC_KEYS`/`ENC_KEY_ACTIVE`) overwrite their TOML
    # equivalents in `[cluster]`/`[encryption]`, so they could in theory
    # be moved into `settings` or `BOOTSTRAP_DIR`. Both options would
    # serialize the secrets into `/nix/store` (world-readable), which we
    # explicitly want to avoid. Keeping them in this oneshot's
    # root-owned `0600` env file is the only place they don't leak — and
    # the operator never has to generate or manage them by hand.
    systemd.services.rauthy-generate-secrets = {
      description = "Generate Rauthy bootstrap secrets if missing";
      wantedBy = [ "rauthy.service" ];
      before = [ "rauthy.service" ];
      partOf = [ "rauthy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/etc/rauthy" ];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
      };
      script = ''
        set -euo pipefail
        umask 077

        touch /etc/rauthy/rauthy.env

        # `cluster.secret_raft` / `cluster.secret_api`: Hiqlite's internal
        # auth tokens for the Raft and API layers. >= 16 chars required;
        # we generate 48.
        if ! grep -q '^HQL_SECRET_RAFT=' /etc/rauthy/rauthy.env; then
          secret=$(${opensslExe} rand -hex 24)
          echo "HQL_SECRET_RAFT=$secret" >> /etc/rauthy/rauthy.env
        fi

        if ! grep -q '^HQL_SECRET_API=' /etc/rauthy/rauthy.env; then
          secret=$(${opensslExe} rand -hex 24)
          echo "HQL_SECRET_API=$secret" >> /etc/rauthy/rauthy.env
        fi

        # `encryption.keys` / `encryption.key_active`: ChaCha20Poly1305 key(s)
        # used for encrypting confidential client secrets, sessions, etc.
        # Format is `<id>/<base64-32-bytes>`; the id must match
        # `^[a-zA-Z0-9:_-]{2,20}$` (8 hex chars satisfy that). Multiple keys
        # would be `\n`-separated; a single key is enough at bootstrap, and
        # rotation is a manual operation via the admin UI.
        if ! grep -q '^ENC_KEYS=' /etc/rauthy/rauthy.env; then
          enc_id=$(${opensslExe} rand -hex 4)
          enc_key=$(${opensslExe} rand -base64 32)
          echo "ENC_KEYS=$enc_id/$enc_key" >> /etc/rauthy/rauthy.env
          echo "ENC_KEY_ACTIVE=$enc_id" >> /etc/rauthy/rauthy.env
        fi
      '';
    };

    systemd.services.rauthy = {
      description = "Rauthy OIDC identity provider";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = cfg.environment;

      serviceConfig = {
        Type = "exec";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 300;
        UMask = "0077";

        # `DynamicUser` allocates an ephemeral UID; the matching
        # `StateDirectory` keeps that UID stable across restarts and owns
        # the writable Hiqlite data dir automatically (no `ReadWritePaths`
        # needed under `ProtectSystem = "strict"`).
        DynamicUser = true;
        StateDirectory = "rauthy";
        WorkingDirectory = "/var/lib/rauthy";

        EnvironmentFile = [
          "/etc/rauthy/rauthy.env"
        ]
        ++ lib.optional (cfg.environmentFile != null) cfg.environmentFile;

        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe cfg.package)
          "serve"
          "-c"
          "${configFile}"
        ];

        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        NoNewPrivileges = true;
        PrivateDevices = true;
        PrivateIPC = true;
        PrivateMounts = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelImage = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        LockPersonality = true;
        RemoveIPC = true;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
          "~@resources"
        ];
        SystemCallErrorNumber = "EPERM";
      };

      unitConfig = {
        StartLimitBurst = 5;
        StartLimitIntervalSec = 600;
      };
    };
  };
}
