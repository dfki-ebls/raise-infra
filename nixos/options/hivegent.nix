{
  lib,
  config,
  utils,
  ...
}:
let
  cfg = config.custom.hivegent;

  # Encode a leaf value for pydantic-settings: lists go through JSON
  # (pydantic's default `list[str]` parser), null collapses to empty,
  # and everything else goes through `mkValueStringDefault` — which
  # already handles ints, floats, bools, strings, and store paths the way
  # we want (no quoting, `true`/`false`, etc.).
  encodeValue =
    v:
    if v == null then
      ""
    else if builtins.isList v then
      builtins.toJSON v
    else
      lib.generators.mkValueStringDefault { } v;

  # Flatten an arbitrarily nested settings tree into `{ NAME = "value"; … }`,
  # joining every path segment with `__` (matching pydantic's
  # `env_nested_delimiter`) and uppercasing the whole thing.
  flattenSettings =
    prefix: settings:
    let
      annotated = lib.mapAttrsRecursive (path: value: {
        name = prefix + lib.toUpper (lib.concatStringsSep "__" path);
        value = encodeValue value;
      }) settings;
    in
    lib.listToAttrs (lib.collect (v: v ? name && v ? value) annotated);

  settingsEnv = flattenSettings "HIVEGENT_" cfg.settings;
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
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = lib.literalExpression ''
        {
          auth = {
            disabled = false;
            issuer = "https://dex.example.com";
          };
          cors_origins = [ "https://hivegent.example.com" ];
          llm = {
            model = "qwen3.6-35b-a3b";
            base_url = "http://localhost:18000/v1";
          };
        }
      '';
      description = ''
        Application settings forwarded to the backend as `HIVEGENT_*`
        environment variables. Every path segment is uppercased and
        joined with `__`, matching pydantic's `env_nested_delimiter`
        (e.g. `llm.model` becomes `HIVEGENT_LLM__MODEL`,
        `auth.disabled` becomes `HIVEGENT_AUTH__DISABLED`). Bools render
        as `true`/`false`, lists as JSON; nulls drop to an empty string.

        `auth.disabled = true` bypasses JWT validation entirely and
        treats every request as a synthetic localhost user — only use
        that on developer workstations.

        `data_dir` defaults to the unit's `StateDirectory` and is set
        automatically; override here only if you need a different layout.
      '';
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Additional environment variables set on the systemd unit. Useful
        for non-`HIVEGENT_*` overrides (e.g. `HF_TOKEN`, proxy variables).
        Merged after `settings` and `auth`, so entries here win.
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
        readable by `root`.
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
        # Pydantic settings drive the application; HOME and HF_HOME redirect
        # libreoffice's profile and the docling/sentence-transformers cache
        # away from /var/empty so first-run startup doesn't fail.
        HOME = "/var/lib/hivegent";
        HF_HOME = "/var/cache/hivegent";
        PYTHONUNBUFFERED = "1";
      }
      // settingsEnv
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

        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;

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
