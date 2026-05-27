{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.rauthy;

  format = pkgs.formats.toml { };
  settingsFile = format.generate "rauthy-config.toml" cfg.settings;
  configFile = if cfg.configFile != null then cfg.configFile else settingsFile;

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
    enable = lib.mkEnableOption "Rauthy";

    package = lib.mkPackageOption pkgs "rauthy" { };

    settings = lib.mkOption {
      type = format.type;
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
        `rauthy serve --config-file <file>`. See the upstream reference
        config at
        <https://github.com/sebadob/rauthy/blob/main/book/src/config/config.md>
        for the full list of sections (`bootstrap`, `cluster`, `server`,
        `webauthn`, `dynamic_clients`, `email`, ...).

        Mutually exclusive with `configFile`.

        ::: {.caution}
        Anything in this attrset lands in `/nix/store` and becomes
        world-readable. Use `environmentFile` for secrets, or render the
        config externally and pass it via `configFile`.
        :::
      '';
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.oneOf [
          lib.types.path
          lib.types.str
        ]
      );
      default = null;
      example = "/run/secrets/rauthy.toml";
      description = ''
        Path to a pre-rendered TOML config file. Mutually exclusive with
        `settings`. Useful when the config must contain secrets that
        cannot live in `/nix/store` — e.g. a sops-nix template, since
        `EnvironmentFile` does not interact cleanly with `DynamicUser`
        (see <https://github.com/Mic92/sops-nix/issues/198>).
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.oneOf [
        lib.types.str
        lib.types.path
      ];
      default = "";
      description = ''
        Optional `KEY=VALUE` env file forwarded via `EnvironmentFile`,
        useful for operator-managed secrets like `SMTP_PASSWORD`. Loaded
        *after* the auto-generated `/etc/rauthy/rauthy.env`, so entries
        here win on conflicts. Must be readable by `root` (systemd reads
        it before dropping to the unit's `DynamicUser`).

        Note that `EnvironmentFile` and `DynamicUser` do not always play
        well with sops-nix
        (<https://github.com/Mic92/sops-nix/issues/198>); for secrets
        that need to land in the config itself, prefer `configFile`.
      '';
    };

    enableUnixSocket = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to listen on a UNIX domain socket at
        `/run/rauthy/rauthy.sock` instead of a TCP address.

        Requires `settings.server.scheme` to be `unix_http` or
        `unix_https`.
      '';
    };

    postgresql.createLocally = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to provision a local PostgreSQL database for Rauthy and
        wire `settings.database` to it.

        When enabled, defaults `settings.database` to connect to the host
        Postgres via the Unix socket at `/var/run/postgresql` under a
        `rauthy` role owning a `rauthy` database. Authentication relies on
        Postgres' `peer` rule, which works out of the box because the unit
        runs under `DynamicUser = true` (the resulting OS user name equals
        the unit name and is matched 1:1 against the DB role).

        Adds the role + database via `services.postgresql.ensureUsers` /
        `ensureDatabases` and orders the rauthy unit after
        `postgresql.target` so the setup oneshot has run first.

        Requires `services.postgresql.enable = true` — this option only
        wires Rauthy *into* an existing Postgres, it does not turn one on.
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

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = !(cfg.settings != { } && cfg.configFile != null);
            message = "`custom.rauthy.settings` and `custom.rauthy.configFile` are mutually exclusive.";
          }
          {
            assertion =
              !cfg.enableUnixSocket
              || (
                cfg.settings ? server.scheme
                && (cfg.settings.server.scheme == "unix_http" || cfg.settings.server.scheme == "unix_https")
              );
            message =
              "`custom.rauthy.settings.server.scheme` must be set to 'unix_http' "
              + "or 'unix_https' when `custom.rauthy.enableUnixSocket` is enabled.";
          }
          {
            assertion = cfg.postgresql.createLocally -> config.services.postgresql.enable;
            message =
              "`custom.rauthy.postgresql.createLocally` requires " + "`services.postgresql.enable = true`.";
          }
        ];

        systemd.services.rauthy = {
          description = "Rauthy";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];

          environment = lib.mkMerge [
            # Bootstrap entries are rendered to JSON under a Nix-built dir
            # and injected via env var, which overrides any `bootstrap_dir`
            # set in the TOML config.
            (lib.optionalAttrs (bootstrapData != { }) {
              BOOTSTRAP_DIR = toString (
                pkgs.linkFarm "rauthy-bootstrap" (
                  lib.mapAttrsToList (name: value: {
                    inherit name;
                    path = pkgs.writeText name (builtins.toJSON value);
                  }) bootstrapData
                )
              );
            })
            (lib.mkIf cfg.enableUnixSocket { LISTEN_ADDRESS = "%t/rauthy/rauthy.sock"; })
          ];

          serviceConfig = {
            ExecStart = "${lib.getExe cfg.package} serve --config-file ${configFile}";
            DynamicUser = true;
            StateDirectory = "rauthy";
            WorkingDirectory = "%S/rauthy";
            RuntimeDirectory = lib.mkIf cfg.enableUnixSocket "rauthy";
            RuntimeDirectoryMode = lib.mkIf cfg.enableUnixSocket "750";
            EnvironmentFile = [
              "/etc/rauthy/rauthy.env"
            ]
            ++ lib.optional (cfg.environmentFile != "") cfg.environmentFile;
            # Hardening
            LockPersonality = true;
            MemoryDenyWriteExecute = true;
            NoNewPrivileges = true;
            PrivateDevices = true;
            PrivateMounts = true;
            ProtectClock = true;
            ProtectControlGroups = true;
            ProtectHome = true;
            ProtectHostname = true;
            ProtectKernelLogs = true;
            ProtectKernelModules = true;
            ProtectKernelTunables = true;
            RemoveIPC = true;
            RestrictRealtime = true;
            RestrictSUIDSGID = true;
            CapabilityBoundingSet = "CAP_NET_BIND_SERVICE";
            AmbientCapabilities = "CAP_NET_BIND_SERVICE";
            PrivateTmp = "disconnected";
            ProcSubset = "pid";
            ProtectProc = "invisible";
            ProtectSystem = "strict";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            RestrictNamespaces = [
              "~cgroup"
              "~ipc"
              "~mnt"
              "~net"
              "~pid"
              "~user"
              "~uts"
            ];
            SystemCallArchitectures = "native";
            SystemCallFilter = [
              "~@clock"
              "~@cpu-emulation"
              "~@debug"
              "~@module"
              "~@mount"
              "~@obsolete"
              "~@privileged"
              "~@raw-io"
              "~@reboot"
              "~@swap"
            ];
            UMask = "0077";

            # Additional hardening on top of the upstream set.
            PrivateIPC = true;
            PrivateUsers = true;
            ProtectKernelImage = true;
            SystemCallErrorNumber = "EPERM";
          };
        };
      }

      (lib.mkIf cfg.postgresql.createLocally {
        # Connection defaults for the local Postgres. `mkDefault` on every
        # field so operators can still override the user/database name (or
        # any other knob) via `custom.rauthy.settings.database.*`.
        custom.rauthy.settings.database = {
          hiqlite = lib.mkDefault false;
          pg_host = lib.mkDefault "/var/run/postgresql";
          pg_user = lib.mkDefault "rauthy";
          pg_db_name = lib.mkDefault "rauthy";
          # `validate()` in `rauthy_config.rs` panics if `pg_password` is
          # unset, even though peer auth on the UDS makes the value
          # meaningless — Postgres ignores what the client sends. Any
          # non-empty string keeps the validation happy.
          pg_password = lib.mkDefault "peer";
          # UDS connections cannot do TLS; the default `prefer` would log
          # a noisy fallback on every reconnect.
          pg_tls = lib.mkDefault "disable";
        };

        services.postgresql = {
          ensureDatabases = [ cfg.settings.database.pg_db_name ];
          ensureUsers = [
            {
              name = cfg.settings.database.pg_user;
              ensureDBOwnership = true;
            }
          ];
        };

        # The setup oneshot inside `postgresql.target` runs the
        # `ensureDatabases`/`ensureUsers` SQL, so peer auth has a role to
        # bind to by the time rauthy connects.
        systemd.services.rauthy = {
          after = [ "postgresql.target" ];
          requires = [ "postgresql.target" ];
        };
      })
    ]
  );
}
