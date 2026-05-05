{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.custom.llama-cpp;

  # llama-server uses GNU long options separated by spaces (`--flag value`); booleans
  # render as bare `--flag` for true and `--no-flag` for false. We rewrite false attrs
  # to `no-<flag> = true` before handing them to `toCommandLine` so the latter only ever
  # sees true booleans, which `explicitBool = false` then collapses to `[option]`.
  # `sep = null` keeps option/value as separate argv entries; the resulting list is
  # composed with the executable path and rendered via `utils.escapeSystemdExecArgs`,
  # which applies systemd's exec quoting (not shell quoting) for `ExecStart=`.
  mkArgs =
    attrs:
    lib.cli.toCommandLine
      (name: {
        option = "--${name}";
        sep = null;
        explicitBool = false;
      })
      (
        lib.mapAttrs' (
          k: v: if v == false then lib.nameValuePair "no-${k}" true else lib.nameValuePair k v
        ) attrs
      );

  # No inter-container DNS here, so dots in model names are fine and useful for
  # `qwen3.6-…`-style identifiers. The regex still anchors to systemd-safe characters.
  modelLabel = lib.types.strMatching "[a-zA-Z0-9][a-zA-Z0-9.-]*";

  modelOpts =
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "serving of model ${name}" // {
          default = true;
        };
        name = lib.mkOption {
          type = modelLabel;
          default = name;
          description = ''
            Canonical identifier for this model. Used for the systemd unit name
            (`llama-cpp-<name>`), as the `--alias` advertised by llama-server,
            and as the routing key registered with llmhop (clients select the
            backend by sending this value in the OpenAI `model` field).

            Defaults to the attribute key, so the key itself must be a label of
            alphanumerics, hyphens, and dots starting with an alphanumeric.
          '';
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = ''
            Loopback host port that llama-server binds to. Must be unique per
            enabled model; the gateway (llmhop) reaches each backend at
            `http://127.0.0.1:<port>`.
          '';
        };
        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          example = {
            hf-repo = "unsloth/Qwen3-8B-GGUF:UD-Q4_K_XL";
            temperature = 1.0;
            top-k = 20;
          };
          description = ''
            CLI flags forwarded to `llama-server` for this model.
            Rendered via `lib.cli.toCommandLine`: each entry becomes
            `--<key> <value>`; `true` collapses to `--<key>`, `false` to
            `--no-<key>`, `null` is dropped.
            Merged with `custom.llama-cpp.modelSettings`; per-model entries
            take precedence.
          '';
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Additional environment variables set on this model's service.
            Merged with `custom.llama-cpp.environment`; per-model entries take precedence.
          '';
        };
        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/etc/llama-cpp/qwen.env";
          description = ''
            File in `KEY=VALUE` format forwarded to this model's service via
            `EnvironmentFile`. Loaded after `custom.llama-cpp.environmentFile`,
            so its entries override global ones.
            Must be readable by `root` (systemd reads it before dropping to the
            unit's `DynamicUser`).
          '';
        };
      };
    };

  enabledModels = lib.filterAttrs (_: model: model.enable) cfg.models;

  mkService =
    model:
    let
      subdir = "llama-cpp/${model.name}";
    in
    lib.nameValuePair "llama-cpp-${model.name}" {
      description = "llama.cpp server for ${model.name}";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = {
        LLAMA_CACHE = "/var/cache/${subdir}";
      }
      // cfg.environment
      // model.environment;
      serviceConfig = {
        Type = "idle";
        KillSignal = "SIGINT";
        Restart = "on-failure";
        RestartSec = 30;
        TimeoutStartSec = 3600;
        LimitNOFILE = cfg.openFilesLimit;
        TasksMax = 4096;
        UMask = "0077";

        # Each service gets its own ephemeral UID; per-unit StateDirectory and
        # CacheDirectory pin that UID across restarts and own the writable paths
        # automatically (no `ReadWritePaths` needed under `ProtectSystem = "strict"`).
        # The `parent/leaf` form keeps every model's state and cache under a single
        # `/var/{lib,cache}/llama-cpp/` parent — only the leaf is owned by the
        # DynamicUser, intermediate parents stay root-owned and shared.
        DynamicUser = true;
        StateDirectory = subdir;
        CacheDirectory = subdir;
        WorkingDirectory = "/var/lib/${subdir}";

        EnvironmentFile =
          lib.optional (cfg.environmentFile != null) cfg.environmentFile
          ++ lib.optional (model.environmentFile != null) model.environmentFile;

        ExecStart = utils.escapeSystemdExecArgs (
          [ (lib.getExe' cfg.package "llama-server") ]
          ++ mkArgs (
            {
              host = "127.0.0.1";
              port = model.port;
              alias = model.name;
            }
            // cfg.modelSettings
            // model.settings
          )
        );

        # GPU acceleration needs raw device access (NVIDIA `/dev/nvidia*`); the upstream
        # NixOS module disables PrivateDevices for the same reason.
        PrivateDevices = false;

        # hardening — extends the upstream `services.llama-cpp` baseline.
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        # llama-server only ever needs to listen on its own port; everything
        # else (including outbound TCP for HF downloads) is unaffected since
        # `SocketBind*` only gates `bind()`. Covers IPv4 and IPv6.
        SocketBindDeny = "any";
        SocketBindAllow = "tcp:${toString model.port}";
        NoNewPrivileges = true;
        PrivateIPC = true;
        PrivateMounts = true;
        PrivateTmp = true;
        PrivateUsers = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = true;
        ProtectKernelImage = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectSystem = "strict";
        MemoryDenyWriteExecute = true;
        LockPersonality = true;
        RemoveIPC = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "~@privileged"
        ];
        SystemCallErrorNumber = "EPERM";
        ProtectProc = "invisible";
        ProtectHostname = true;
        ProcSubset = "pid";
      };
      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = 3600;
      };
    };
in
{
  options.custom.llama-cpp = {
    enable = lib.mkEnableOption "llama.cpp model serving via systemd, fronted by llmhop";

    package = lib.mkPackageOption pkgs "llama-cpp" { };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Environment variables set on every model service.
        Merged with `custom.llama-cpp.models.<name>.environment`; per-model entries take precedence.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/llama-cpp/.env";
      description = ''
        File in `KEY=VALUE` format forwarded to every service via `EnvironmentFile`.
        Use for secrets managed by sops-nix/agenix, e.g. a file containing
        `HF_TOKEN=<token>` to access gated Hugging Face repositories.
        Loaded before `custom.llama-cpp.models.<name>.environmentFile`, so per-model
        files override these entries.
        Must be readable by `root` (systemd reads it before dropping to the
        unit's `DynamicUser`).
      '';
    };

    modelSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        flash-attn = "on";
        n-gpu-layers = 99;
        parallel = 4;
      };
      description = ''
        CLI flags forwarded to `llama-server` for every model.
        Rendered via `lib.cli.toCommandLine`: each entry becomes
        `--<key> <value>`; `true` collapses to `--<key>`, `false` to
        `--no-<key>`, `null` is dropped.
        Merged with `custom.llama-cpp.models.<name>.settings`; per-model entries
        take precedence.
      '';
    };

    openFilesLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1048576;
      description = ''
        File descriptor limit (`LimitNOFILE`) applied to every llama-server systemd unit.
        Increase if llama-server logs `accept: Too many open files` under concurrent load.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule modelOpts);
      default = { };
      example = lib.literalExpression ''
        {
          "qwen3-8b" = {
            port = 18001;
            settings = {
              hf-repo = "unsloth/Qwen3-8B-GGUF:UD-Q4_K_XL";
              temperature = 1.0;
              top-k = 20;
            };
          };
        }
      '';
      description = ''
        Models to serve.
        Each entry produces one systemd service running `llama-server`; the
        attribute name is the routing key surfaced through llmhop and the OpenAI
        `model` field.
      '';
    };

    llmhop.addModels = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to register every enabled model with `services.llmhop.settings.models`,
        pointing at its loopback `port`. The rest of the llmhop service (enable, listen,
        TLS, etc.) is left to the user to configure separately.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          let
            ports = map (m: m.port) (lib.attrValues enabledModels);
          in
          lib.length (lib.unique ports) == lib.length ports;
        message = "custom.llama-cpp.models: each model must use a unique `port`.";
      }
    ];

    systemd.services = lib.mapAttrs' (_: mkService) enabledModels;

    services.llmhop.settings.models = lib.mkIf cfg.llmhop.addModels (
      lib.mapAttrs (_: model: {
        url = "http://127.0.0.1:${toString model.port}";
      }) enabledModels
    );
  };
}
