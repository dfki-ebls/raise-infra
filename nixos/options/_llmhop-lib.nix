{ lib }:
let
  inherit (lib)
    attrValues
    filterAttrs
    hasPrefix
    length
    mapAttrs
    mapAttrs'
    mkEnableOption
    mkIf
    mkMerge
    mkOption
    nameValuePair
    optional
    removePrefix
    types
    unique
    ;

  # ─── Shared building blocks (private) ────────────────────────────────

  # Permissive label for unit and routing-key names. Allows dots so
  # `qwen3.6-…`-style version suffixes work.
  modelLabel = types.strMatching "[[:alnum:]][[:alnum:].-]*";

  # Top-level options every backend exposes, regardless of kind.
  baseOptions =
    { backend }:
    {
      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = ''
          Environment variables set on every model service.
          Merged with `services.llmhop.${backend}.models.<name>.environment`; per-model
          entries take precedence.
        '';
      };
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/etc/${backend}/.env";
        description = ''
          File in `KEY=VALUE` format forwarded to every service.
          Use for secrets managed by sops-nix/agenix, e.g. a file containing
          `HF_TOKEN=<token>` to access gated Hugging Face repositories.
          Loaded before `services.llmhop.${backend}.models.<name>.environmentFile`, so
          per-model files override these entries.
        '';
      };
      modelSettings = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = ''
          CLI flags forwarded to the model server for every model.
          `true` collapses to `--<key>`; `null` and `false` are dropped (write
          the negated key explicitly, e.g. `"no-mmap" = true;`, when the upstream
          CLI registers a `--no-<key>` form).
          Merged with `services.llmhop.${backend}.models.<name>.settings`; per-model
          entries take precedence.
        '';
      };
      openFilesLimit = mkOption {
        type = types.ints.positive;
        default = 1048576;
        description = ''
          File descriptor limit (`LimitNOFILE`) applied to every ${backend} systemd unit.
          Increase if the server logs `accept: Too many open files` under concurrent load.
        '';
      };
    };

  # Per-model options every backend exposes, regardless of kind.
  baseModelOptions =
    {
      backend,
      name,
    }:
    {
      enable = mkEnableOption "serving of model ${name}" // {
        default = true;
      };
      name = mkOption {
        type = modelLabel;
        default = name;
        description = ''
          Canonical identifier for this model. Used for the unit name
          (`${backend}-<name>`) and as the routing key registered with llmhop
          (clients select the backend by sending this value in the OpenAI
          `model` field).

          Defaults to the attribute key, so the key itself must match the
          required label format.
        '';
      };
      settings = mkOption {
        type = types.attrsOf types.anything;
        default = { };
        description = ''
          CLI flags forwarded to the model server for this model.
          `true` collapses to `--<key>`; `null` and `false` are dropped (write
          the negated key explicitly, e.g. `"no-mmap" = true;`, when the upstream
          CLI registers a `--no-<key>` form).
          Merged with `services.llmhop.${backend}.modelSettings`; per-model entries
          take precedence.
        '';
      };
      environment = mkOption {
        type = types.attrsOf types.str;
        default = { };
        description = ''
          Additional environment variables set on this model's service.
          Merged with `services.llmhop.${backend}.environment`; per-model entries
          take precedence.
        '';
      };
      environmentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          File in `KEY=VALUE` format forwarded to this model's service.
          Loaded after `services.llmhop.${backend}.environmentFile`, so its entries
          override global ones. Must be readable by the user systemd reads it as.
        '';
      };
    };

  # Defaults applied to every worker, scoped by the systemd unit-file section
  # they belong to. Worker helpers merge these into the corresponding *Config
  # attribute before layering caller overrides on top.

  # `[Unit]` defaults: hard-fail after 3 errors/hour so journald surfaces the
  # underlying error instead of an endless restart loop.
  sharedUnitConfig = {
    StartLimitBurst = 3;
    StartLimitIntervalSec = 3600;
  };

  # `[Service]` defaults: hour-long `TimeoutStartSec` covers cold-start model
  # downloads + GPU memory profiling; `RestartSec = 30` debounces crash loops.
  sharedServiceConfig = {
    TimeoutStartSec = 3600;
    RestartSec = 30;
  };

  # Enabled-model subset shared by every registry helper and by backends'
  # iteration over their model set.
  enabledModels = cfg: filterAttrs (_: m: m.enable) cfg.models;

  # Per-backend port-uniqueness assertion. Reuses `mkPortRegistry` so the
  # local check sees exactly the same ports as the global cross-backend one.
  mkPortsAssertion =
    {
      backend,
      cfg,
      extras ? { },
      portsMessage ? null,
    }:
    let
      ports = attrValues (mkPortRegistry {
        inherit backend cfg extras;
      });
    in
    {
      assertion = length (unique ports) == length ports;
      message =
        if portsMessage != null then
          portsMessage
        else
          "services.llmhop.${backend}.models: each model must use a unique `port`.";
    };

  # Labeled fragment contributed to `services.llmhop.portsRegistry` for the
  # global cross-backend uniqueness check. Keys are `<backend>/<modelName>`
  # for models and `<backend>/<extraLabel>` for auxiliary components.
  mkPortRegistry =
    {
      backend,
      cfg,
      extras ? { },
    }:
    let
      modelEntries = mapAttrs' (name: m: nameValuePair "${backend}/${name}" m.port) (enabledModels cfg);
      extraEntries = mapAttrs' (name: port: nameValuePair "${backend}/${name}" port) extras;
    in
    modelEntries // extraEntries;

  # `services.llmhop.settings.models` fragment shared by every backend.
  mkLlmhopRegistry =
    { cfg }: mapAttrs (_: m: { url = "http://127.0.0.1:${toString m.port}"; }) (enabledModels cfg);

  # Cross-cutting NixOS fragment every backend (quadlet or systemd) emits:
  # local port-uniqueness assertion plus the llmhop model + ports-registry
  # contributions. Backend-specific extras (quadlet tmpfiles/user/group,
  # quadlet-enabled assertion, ...) layer on top via `lib.mkMerge`.
  mkSharedConfig =
    {
      backend,
      cfg,
      extras ? { },
      portsMessage ? null,
    }:
    {
      assertions = [
        (mkPortsAssertion {
          inherit
            backend
            cfg
            extras
            portsMessage
            ;
        })
      ];
      services.llmhop = {
        settings.models = mkLlmhopRegistry { inherit cfg; };
        portsRegistry = mkPortRegistry { inherit backend cfg extras; };
      };
    };
in
{
  inherit enabledModels;

  # ─── CLI helpers ──────────────────────────────────────────────────────

  # `lib.cli.toCommandLine` drops `false` values entirely. For backends whose
  # boolean flags follow Python argparse's `BooleanOptionalAction` pattern
  # (i.e. paired `--key` / `--no-key` flags), we want `key = false` to produce
  # `--no-key` instead of being silently dropped. This helper rewrites
  # `{ key = false; }` to `{ "no-key" = true; }` (and vice-versa for keys
  # already prefixed with `no-`); other values pass through unchanged.
  #
  # Only apply this to backends that universally use `BooleanOptionalAction`
  # (e.g. vLLM, llama.cpp). Backends like SGLang that use plain `store_true`
  # with `--enable-X` / `--disable-X` pairs would receive invalid `--no-X`
  # flags and reject the command line.
  flipBoolFlags = mapAttrs' (
    name: value:
    if value == false then
      nameValuePair (if hasPrefix "no-" name then removePrefix "no-" name else "no-${name}") true
    else
      nameValuePair name value
  );

  # ─── Image refs ───────────────────────────────────────────────────────

  # Resolve `image:tag` or `image@digest`. `tag` and `digest` are mutually
  # exclusive; `defaultTag` is used when both are null.
  resolveImageRef =
    {
      image,
      tag,
      digest,
      defaultTag ? null,
      label,
    }:
    if tag != null && digest != null then
      throw "${label}: `tag` and `digest` are mutually exclusive."
    else if digest != null then
      "${image}@${digest}"
    else if tag != null then
      "${image}:${tag}"
    else if defaultTag != null then
      "${image}:${defaultTag}"
    else
      throw "${label}: one of `tag`, `digest`, or a default tag must be provided.";

  # ─── Quadlet (container-based) ───────────────────────────────────────

  quadlet = {
    # Top-level options for a quadlet-based backend. Spread under
    # `options.services.llmhop.<backend>` via `//`; the caller adds `enable`,
    # `models`, and any backend-specific extras (gateway sub-options, etc.).
    # `cfg` (the corresponding `config.services.llmhop.<backend>`) is passed
    # in so the GID-side options can lazily default to their UID counterparts.
    mkOptions =
      {
        backend,
        cfg,
        defaultImage,
        defaultCacheDir,
        tagExample ? "latest",
      }:
      (baseOptions { inherit backend; })
      // {
        user = mkOption {
          type = types.str;
          default = backend;
          defaultText = lib.literalExpression "backend";
          description = ''
            Dedicated system user that owns the ${backend} cache directory and that
            container root is mapped to via `--uidmap`. Defaults to the backend
            name; override to point at a user the deployer manages externally
            (in which case the matching `users.users.<name>` and
            `users.groups.<name>` declarations become the deployer's
            responsibility).
          '';
        };
        uid = mkOption {
          type = types.ints.unsigned;
          example = 503;
          description = ''
            Host UID assigned to `services.llmhop.${backend}.user` and used as the
            inner-to-outer mapping target in `--uidmap`.
            Required — pick a value that does not clash with other system users on the
            host.
          '';
        };
        group = mkOption {
          type = types.str;
          default = cfg.user;
          defaultText = lib.literalExpression "config.services.llmhop.${backend}.user";
          description = ''
            Primary group for `services.llmhop.${backend}.user`.
            Defaults to the user name (matching the typical 1:1 user/group layout).
          '';
        };
        gid = mkOption {
          type = types.ints.unsigned;
          default = cfg.uid;
          defaultText = lib.literalExpression "config.services.llmhop.${backend}.uid";
          description = ''
            Host GID assigned to `services.llmhop.${backend}.group` and used as the
            inner-to-outer mapping target in `--gidmap`. Defaults to `uid`.
          '';
        };
        image = mkOption {
          type = types.str;
          default = defaultImage;
          description = "Container image used for every model worker.";
        };
        tag = mkOption {
          type = types.str;
          example = tagExample;
          description = ''
            Default tag of the container image used for models that do not set their own
            `tag` or `digest`.
          '';
        };
        cacheDir = mkOption {
          type = types.path;
          default = defaultCacheDir;
          description = "Host directory bind-mounted as the Hugging Face cache for every worker.";
        };
        subUidStart = mkOption {
          type = types.ints.unsigned;
          example = 300000;
          description = ''
            First host UID of the subordinate range mapped into every container.
            Container UIDs ≥1 are mapped to `subUidCount` consecutive host IDs starting here.
            Required — pick a value clear of NixOS system users (`<1000`), regular login
            UIDs, and other backends' subordinate ranges on the same host.
          '';
        };
        subUidCount = mkOption {
          type = types.ints.positive;
          default = 65536;
          description = ''
            Size of the subordinate UID range mapped into every container.
            65536 covers the full unprivileged ID space inside the namespace.
          '';
        };
        subGidStart = mkOption {
          type = types.ints.unsigned;
          default = cfg.subUidStart;
          defaultText = lib.literalExpression "config.services.llmhop.${backend}.subUidStart";
          description = ''
            First host GID of the subordinate range mapped into every container.
            Defaults to `subUidStart` — most setups keep the UID and GID ranges aligned.
          '';
        };
        subGidCount = mkOption {
          type = types.ints.positive;
          default = cfg.subUidCount;
          defaultText = lib.literalExpression "config.services.llmhop.${backend}.subUidCount";
          description = ''
            Size of the subordinate GID range mapped into every container.
            Defaults to `subUidCount`.
          '';
        };
        startupOrdering = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to chain enabled model services by ascending `port` during startup.
            GPU-memory profiling races otherwise: two workers booting on the same device
            each see it as fully free and race to claim their share, leading to OOM.
            Disable only when each model has its own dedicated GPU (`gpus = [ N ]`).
          '';
        };
      };

    # Per-model submodule for a quadlet-based backend (without `port`, since
    # its description varies per backend). Use as one entry of `imports` inside
    # `lib.types.submodule`.
    mkModelSubmodule =
      { backend }:
      { name, ... }:
      {
        options = (baseModelOptions { inherit backend name; }) // {
          model = mkOption {
            type = types.str;
            example = "Qwen/Qwen2.5-7B-Instruct";
            description = "Hugging Face repo id (or local path) passed to the model server.";
          };
          tag = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Tag of the container image used for this model.
              Mutually exclusive with `digest`.
            '';
          };
          digest = mkOption {
            type = types.nullOr types.str;
            default = null;
            example = "sha256:a73fb0b9046fee099f7c1829d2548e6cc1740f4c2776a6855fa659ae5d0deb49";
            description = ''
              Immutable digest of the container image (e.g. `sha256:…`).
              Mutually exclusive with `tag`.
            '';
          };
          gpus = mkOption {
            type = with types; either (enum [ "all" ]) (listOf int);
            default = "all";
            description = "GPU device(s) exposed to the container via the NVIDIA CDI provider.";
          };
          shmSize = mkOption {
            type = types.str;
            default = "32g";
            example = "64g";
            description = ''
              Size of the container's private `/dev/shm` tmpfs.
              PyTorch and friends use shared memory for NCCL/tensor-parallel inference;
              upstream recommends 32g (or `--ipc=host`). A private tmpfs is preferred for
              isolation: raise the value for larger models or higher tensor-parallel sizes.
            '';
          };
        };
      };

    # Render a Quadlet container worker fragment. Returns
    # `{ serviceConfig, unitConfig, containerConfig }` with the shared baseline
    # merged in; caller overrides win.
    mkWorker =
      {
        openFilesLimit,
        healthPort,
        healthPath ? "/health",
        healthStartPeriod ? "30m",
        serviceConfig ? { },
        unitConfig ? { },
        containerConfig ? { },
      }:
      {
        serviceConfig =
          sharedServiceConfig
          // {
            LimitNOFILE = openFilesLimit;
          }
          // serviceConfig;
        unitConfig = sharedUnitConfig // unitConfig;
        # `[Container]` defaults: minimal hardening (podman handles the rest at
        # the container level) plus an HTTP `/health` probe.
        containerConfig = {
          NoNewPrivileges = true;
          DropCapability = "all";
          Notify = "healthy";
          HealthCmd = "curl --fail --silent --show-error http://localhost:${toString healthPort}${healthPath}";
          HealthStartPeriod = healthStartPeriod;
          HealthInterval = "10s";
          HealthTimeout = "5s";
        }
        // containerConfig;
      };

    # Common Quadlet `containerConfig` fields for a model worker — covers
    # UID/GID mapping, image resolution, pull policy, GPU CDI device, HF cache
    # bind-mount, env-file/env, shm size, and host ulimits. Spread together
    # with backend-specific extras (`PublishPort`, `Exec`, ...) via `//`.
    #
    # Digest-locked images stay pinned (`Pull=missing`); tag-tracking images
    # refresh on rebuild (`Pull=newer`). EnvironmentFile order is
    # global-then-per-model so per-model entries win.
    mkContainerArgs =
      {
        backend,
        cfg,
        model,
      }:
      {
        UIDMap = [
          "0:${toString cfg.uid}:1"
          "1:${toString cfg.subUidStart}:${toString cfg.subUidCount}"
        ];
        GIDMap = [
          "0:${toString cfg.gid}:1"
          "1:${toString cfg.subGidStart}:${toString cfg.subGidCount}"
        ];
        Image =
          if model.tag != null && model.digest != null then
            throw "services.llmhop.${backend}.models.${model.name}: `tag` and `digest` are mutually exclusive."
          else if model.digest != null then
            "${cfg.image}@${model.digest}"
          else
            "${cfg.image}:${if model.tag != null then model.tag else cfg.tag}";
        Pull = if model.digest != null then "missing" else "newer";
        AddDevice =
          if model.gpus == "all" then
            [ "nvidia.com/gpu=all" ]
          else
            map (i: "nvidia.com/gpu=${toString i}") model.gpus;
        Volume = [ "${cfg.cacheDir}:/root/.cache/huggingface" ];
        EnvironmentFile =
          optional (cfg.environmentFile != null) cfg.environmentFile
          ++ optional (model.environmentFile != null) model.environmentFile;
        Environment = cfg.environment // model.environment;
        ShmSize = model.shmSize;
        Ulimit = "host";
      };

    # Cross-cutting NixOS config produced by every quadlet backend: assertions
    # (quadlet-enabled + port uniqueness), llmhop registration, the port
    # registry contribution, tmpfiles, and — when the user hasn't been
    # customised away from the backend default — the system user/group.
    # Compose with backend-specific config via `lib.mkMerge`; list-typed
    # options like `assertions` concatenate naturally.
    #
    # `extras` is a labeled attrset of auxiliary host ports (e.g.
    # `{ gateway = 30000; }`) that participates in both the local and global
    # port-uniqueness checks. The llmhop registration writes are harmless
    # when `services.llmhop.enable = false` (the upstream module guards its
    # service on `enable`), so backends can be used standalone without gating.
    #
    # If the deployer overrides `cfg.user` away from `backend`, they are
    # responsible for declaring the matching `users.users.<name>` (with the
    # right uid + sub-id ranges) and `users.groups.<group>` themselves.
    mkConfig =
      {
        backend,
        cfg,
        config,
        description,
        extras ? { },
        portsMessage ? null,
      }:
      mkMerge [
        (mkSharedConfig {
          inherit
            backend
            cfg
            extras
            portsMessage
            ;
        })
        {
          assertions = [
            {
              assertion = config.virtualisation.quadlet.enable;
              message = "services.llmhop.${backend} requires virtualisation.quadlet.enable.";
            }
          ];

          systemd.tmpfiles.settings."10-${backend}".${cfg.cacheDir}.d = {
            user = cfg.user;
            group = cfg.group;
            mode = "0700";
          };

          users.users = mkIf (cfg.user == backend) {
            ${cfg.user} = {
              inherit description;
              uid = cfg.uid;
              isSystemUser = true;
              group = cfg.group;
              subUidRanges = [
                {
                  startUid = cfg.subUidStart;
                  count = cfg.subUidCount;
                }
              ];
              subGidRanges = [
                {
                  startGid = cfg.subGidStart;
                  count = cfg.subGidCount;
                }
              ];
            };
          };
          users.groups = mkIf (cfg.user == backend) {
            ${cfg.group}.gid = cfg.gid;
          };
        }
      ];
  };

  # ─── Systemd (host-process) ──────────────────────────────────────────

  systemd = {
    # Top-level options for a systemd-service backend. Just the shared base —
    # nothing container-specific.
    mkOptions = { backend }: baseOptions { inherit backend; };

    # Per-model submodule for a systemd-service backend (without `port`).
    mkModelSubmodule =
      { backend }:
      { name, ... }:
      {
        options = baseModelOptions { inherit backend name; };
      };

    # Render a systemd worker unit fragment. Returns
    # `{ serviceConfig, unitConfig }` with the shared baseline plus full
    # systemd-exec(5) hardening merged in; caller overrides win.
    mkWorker =
      {
        openFilesLimit,
        serviceConfig ? { },
        unitConfig ? { },
      }:
      {
        # `[Service]` defaults: shared timing, full hardening (podman handles
        # its own isolation for containers, so quadlet workers skip this layer),
        # and the file-descriptor limit. `SocketBind*` only gates `bind()`, so
        # outbound connections (e.g. HF downloads) are unaffected; the caller
        # adds `SocketBindAllow` for its listener.
        serviceConfig =
          sharedServiceConfig
          // {
            LimitNOFILE = openFilesLimit;
            CapabilityBoundingSet = "";
            AmbientCapabilities = "";
            RestrictAddressFamilies = [
              "AF_INET"
              "AF_INET6"
              "AF_UNIX"
            ];
            SocketBindDeny = "any";
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
          }
          // serviceConfig;
        unitConfig = sharedUnitConfig // unitConfig;
      };

    # Cross-cutting NixOS config produced by every systemd backend: port
    # uniqueness assertion (local + global registry) plus llmhop
    # registration. No tmpfiles/user/group: systemd backends rely on
    # `DynamicUser` per-service.
    mkConfig = { backend, cfg }: mkSharedConfig { inherit backend cfg; };
  };
}
