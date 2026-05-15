{
  lib,
  pkgs,
  config,
  utils,
  ...
}:
let
  cfg = config.custom.hivegent;

  tomlFormat = pkgs.formats.toml { };
  configFile = tomlFormat.generate "hivegent-config.toml" cfg.settings;
in
{
  options.custom.hivegent = {
    enable = lib.mkEnableOption "the Hivegent backend service";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        Backend package providing `bin/hivegent`. The wrapper must already
        contain every CLI tool the backend invokes via subprocesses (jq,
        pandoc, ripgrep, libreoffice).
      '';
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address `hivegent serve` binds to. Stays on the loopback by default;
        external traffic should reach the API through a reverse proxy.
      '';
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8000;
      description = ''
        Port `hivegent serve` listens on. Mirrored into
        `mcp.base_url`'s default and into the systemd `SocketBindAllow`.
      '';
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = { };
      example = lib.literalExpression ''
        {
          auth = {
            enable = true;
            issuer = "https://auth.example.com";
          };
          llm = {
            model = "qwen3.6-35b-a3b";
            base_url = "http://localhost:18000/v1";
          };
        }
      '';
      description = ''
        Hivegent TOML config rendered into the Nix store and passed via
        `HIVEGENT_CONFIG_FILE`. Nested attribute sets become TOML tables.

        Do NOT put secrets here — anything in this attrset lands in
        `/nix/store`. Use `environmentFile` for `HIVEGENT_*` overrides
        (e.g. `HIVEGENT_MCP__CLIENT_SECRET`); env vars take precedence
        over the TOML file.

        `auth.enable = false` bypasses JWT validation entirely and
        treats every request as a synthetic localhost user — only use
        that on developer workstations.

        `data_dir` defaults to the unit's `StateDirectory`; override
        here only if you need a different layout.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Plain environment variables set on the unit. Useful for non-secret
        `HIVEGENT_*` overrides of TOML values, or for unrelated vars like
        `HF_TOKEN` and proxy settings.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/hivegent/hivegent.env";
      description = ''
        File in `KEY=VALUE` format forwarded via `EnvironmentFile`. Use it
        for secrets — API keys, MCP client secrets, OIDC client secrets —
        so they never land in the Nix store. Loaded by systemd before the
        process drops to the unit's `DynamicUser`, so the file must be
        readable by `root`. Missing files are tolerated (systemd's `-`
        prefix) so the unit still starts before an operator-managed
        secret file has been created.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    custom.hivegent.settings.data_dir = lib.mkDefault "/var/lib/hivegent";

    systemd.services.hivegent = {
      description = "Hivegent backend";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      environment = {
        # HOME and HF_HOME redirect libreoffice's profile and the
        # docling/sentence-transformers cache away from /var/empty so
        # first-run startup doesn't fail.
        HOME = "/var/lib/hivegent";
        HF_HOME = "/var/cache/hivegent";
        PYTHONUNBUFFERED = "1";
        HIVEGENT_CONFIG_FILE = "${configFile}";
      }
      // cfg.environment;

      serviceConfig = {
        Type = "exec";
        Restart = "on-failure";
        RestartSec = 5;
        TimeoutStartSec = 600;
        UMask = "0077";

        # `DynamicUser` allocates an ephemeral UID; the matching
        # `StateDirectory`/`CacheDirectory` keep that UID stable across
        # restarts and own the writable paths automatically (no
        # `ReadWritePaths` needed under `ProtectSystem = "strict"`).
        DynamicUser = true;
        StateDirectory = "hivegent";
        CacheDirectory = "hivegent";
        WorkingDirectory = "/var/lib/hivegent";

        EnvironmentFile = lib.optional (cfg.environmentFile != null) "-${cfg.environmentFile}";

        ExecStart = utils.escapeSystemdExecArgs [
          (lib.getExe' cfg.package "hivegent")
          "serve"
          "--host"
          cfg.host
          "--port"
          (toString cfg.port)
        ];

        # Listen only on the configured port; everything else (outbound
        # HTTP to llama.cpp, Hugging Face, the OIDC issuer) is unaffected
        # because `SocketBind*` only gates `bind()`.
        SocketBindDeny = "any";
        SocketBindAllow = "tcp:${toString cfg.port}";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
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
