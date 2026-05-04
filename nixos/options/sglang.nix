{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.custom.sglang;

  # SGLang/gateway use GNU long options with `=` separators; null/false attrs are dropped.
  # Lists are not supported here — `toCommandLineShell` would render them as repeated
  # `--flag=v` entries, which breaks argparse `nargs='+'` flags like `--worker-urls`.
  mkArgs = lib.cli.toCommandLineShell (name: {
    option = "--${name}";
    sep = "=";
    explicitBool = false;
  });

  # aardvark-dns rejects dots in container names, so model `name`s must be DNS labels.
  containerName = name: "sglang-${name}";

  dnsLabel = lib.types.strMatching "[a-zA-Z0-9][a-zA-Z0-9-]*";

  modelOpts =
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "serving of model ${name}" // {
          default = true;
        };
        name = lib.mkOption {
          type = dnsLabel;
          default = name;
          description = ''
            Canonical identifier for this model. Used for the container/unit name
            (`sglang-<name>`), as the inter-container DNS label, and as the routing
            name advertised to the SGL Model Gateway via `--served-model-name`.

            Defaults to the attribute key, so the key itself must be a DNS label
            (starts with an alphanumeric, then alphanumerics or hyphens; no dots).
            This is required by aardvark-dns, which rejects dots in container names.
          '';
        };
        model = lib.mkOption {
          type = lib.types.str;
          example = "Qwen/Qwen2.5-7B-Instruct";
          description = "Hugging Face repo id (or local path) passed to SGLang as `--model-path`.";
        };
        tag = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Tag of the SGLang container image used for this model.
            Mutually exclusive with `digest`.
          '';
        };
        digest = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "sha256:a73fb0b9046fee099f7c1829d2548e6cc1740f4c2776a6855fa659ae5d0deb49";
          description = ''
            Immutable digest of the SGLang container image (e.g. `sha256:…`).
            Mutually exclusive with `tag`.
          '';
        };
        gpus = lib.mkOption {
          type = with lib.types; either (enum [ "all" ]) (listOf int);
          default = "all";
          description = "GPU device(s) exposed to the container via the NVIDIA CDI provider.";
        };
        settings = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          example = {
            mem-fraction-static = 0.6;
            cuda-graph-max-bs = 4;
          };
          description = ''
            Additional CLI flags forwarded to `sglang serve`.
            Rendered via `lib.cli.toCommandLineShellGNU`; entries with `false` or `null` are omitted.
            Merged with `custom.sglang.modelSettings`; these entries take precedence.
          '';
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            SGLANG_ENABLE_SPEC_V2 = "1";
          };
          description = ''
            Additional environment variables set on the container.
            Merged with `custom.sglang.environment`; these entries take precedence.
          '';
        };
        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/etc/sglang/qwen.env";
          description = ''
            File in `KEY=VALUE` format forwarded to this model's container via `--env-file`.
            Loaded after `custom.sglang.environmentFile`, so its entries override global ones.
            Must be readable by the `sglang` user.
          '';
        };
        shmSize = lib.mkOption {
          type = lib.types.str;
          default = "32g";
          example = "64g";
          description = ''
            Size of the container's private `/dev/shm` tmpfs.
            SGLang and PyTorch use shared memory for NCCL/tensor-parallel inference; upstream
            recommends 32g (or `--ipc=host`). A private tmpfs is preferred for isolation.
          '';
        };
      };
    };

  # Sort by name so the After= chain below is deterministic across rebuilds.
  models = lib.pipe cfg.models [
    lib.attrValues
    (lib.filter (model: model.enable))
    (lib.sort (a: b: a.name < b.name))
  ];

  cdiDevices =
    model:
    if model.gpus == "all" then
      [ "nvidia.com/gpu=all" ]
    else
      map (i: "nvidia.com/gpu=${toString i}") model.gpus;

  imageRef =
    model:
    if model.tag != null && model.digest != null then
      throw "custom.sglang.models.${model.name}: `tag` and `digest` are mutually exclusive."
    else if model.digest != null then
      "${cfg.image}@${model.digest}"
    else
      "${cfg.image}:${if model.tag != null then model.tag else cfg.tag}";

  # Workers keep the rootfs writable so torch's compile cache and SGLang's scratch files
  # don't fail; the gateway pins ReadOnly= separately as a stateless Rust binary.
  hardening = {
    NoNewPrivileges = true;
    DropCapability = "all";
  };

  modelExec =
    model:
    mkArgs (
      {
        model-path = model.model;
        served-model-name = model.name;
        host = "0.0.0.0";
        port = cfg.workerPort;
      }
      // cfg.modelSettings
      // model.settings
    );

  workerUrl = model: "http://${containerName model.name}:${toString cfg.workerPort}";

  mkModelContainer =
    i: model:
    let
      cname = containerName model.name;
    in
    lib.nameValuePair cname {
      uid = config.users.users.${cfg.user}.uid;
      containerConfig = hardening // {
        ContainerName = cname;
        Image = imageRef model;
        Pull = if model.digest != null then "missing" else "newer";
        Network = "${cfg.networkName}.network";
        AddDevice = cdiDevices model;
        Volume = [ "${cfg.cacheDir}:/root/.cache/huggingface" ];
        EnvironmentFile =
          lib.optional (cfg.environmentFile != null) cfg.environmentFile
          ++ lib.optional (model.environmentFile != null) model.environmentFile;
        Environment = cfg.environment // model.environment;
        ShmSize = model.shmSize;
        Ulimit = "host";
        Notify = "healthy";
        HealthCmd = "curl --fail --silent --show-error http://localhost:${toString cfg.workerPort}/health";
        HealthStartPeriod = "30m";
        HealthInterval = "10s";
        HealthTimeout = "5s";
        # `lmsysorg/sglang`'s default entrypoint isn't the launcher we want.
        # The new `sglang serve` CLI emits a deprecation warning for this path,
        # but the `sglang` console script is missing from the `*-runtime` image
        # and `sglang.cli.main` lacks a `__main__` guard, so `launch_server`
        # remains the only working invocation here.
        Entrypoint = lib.toJSON [
          "sglang"
          "serve"
        ];
        Exec = modelExec model;
      };
      serviceConfig = {
        TimeoutStartSec = 3600;
        RestartSec = 30;
        LimitNOFILE = cfg.openFilesLimit;
      };
      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = 3600;
        # Chain ascending so each worker finishes GPU-memory profiling before the next starts.
        After = [
          "${cfg.networkName}-network.service"
        ]
        ++
          lib.optional (cfg.startupOrdering && i > 0)
            "${containerName (lib.elemAt models (i - 1)).name}.service";
        Requires = [ "${cfg.networkName}-network.service" ];
      };
    };

  gatewayImageRef =
    if cfg.gateway.tag != null && cfg.gateway.digest != null then
      throw "custom.sglang.gateway: `tag` and `digest` are mutually exclusive."
    else if cfg.gateway.digest != null then
      "${cfg.gateway.image}@${cfg.gateway.digest}"
    else
      "${cfg.gateway.image}:${if cfg.gateway.tag != null then cfg.gateway.tag else "latest"}";

  # The gateway calls /get_model_info on each `worker-urls` entry and uses the worker's
  # `--served-model-name` as the routing key — a fully declarative IGW dispatch table.
  gatewayBaseSettings = {
    host = "0.0.0.0";
    port = cfg.gateway.port;
    prometheus-host = if cfg.gateway.enableMetrics then "0.0.0.0" else null;
    prometheus-port = if cfg.gateway.enableMetrics then cfg.gateway.metricsPort else null;
    enable-igw = true;
  };

  # `--worker-urls` uses argparse `nargs='*'` and must be appended manually so the URLs
  # become separate argv entries; `toCommandLineShell` would shell-escape them into one.
  gatewayExec =
    mkArgs (gatewayBaseSettings // cfg.gateway.settings)
    +
      lib.optionalString (models != [ ])
        " ${lib.escapeShellArgs ([ "--worker-urls" ] ++ map workerUrl models)}";

  gatewayName = containerName "gateway";
  workerServices = map (m: "${containerName m.name}.service") models;

  mkGatewayContainer = lib.nameValuePair gatewayName {
    uid = config.users.users.${cfg.user}.uid;
    containerConfig = hardening // {
      ContainerName = gatewayName;
      Image = gatewayImageRef;
      Pull = if cfg.gateway.digest != null then "missing" else "newer";
      ReadOnly = true;
      Network = "${cfg.networkName}.network";
      # Only the gateway publishes ports; workers stay on the internal network.
      PublishPort = [
        "${cfg.gateway.bindAddress}:${toString cfg.gateway.port}:${toString cfg.gateway.port}"
      ]
      ++ lib.optional cfg.gateway.enableMetrics "${cfg.gateway.bindAddress}:${toString cfg.gateway.metricsPort}:${toString cfg.gateway.metricsPort}";
      EnvironmentFile = lib.optional (cfg.gateway.environmentFile != null) cfg.gateway.environmentFile;
      Environment = cfg.gateway.environment;
      Notify = "healthy";
      HealthCmd = "curl --fail --silent --show-error http://localhost:${toString cfg.gateway.port}/health";
      HealthStartPeriod = "5m";
      HealthInterval = "10s";
      HealthTimeout = "5s";
      Exec = gatewayExec;
    };
    serviceConfig = {
      TimeoutStartSec = 600;
      RestartSec = 10;
      LimitNOFILE = cfg.openFilesLimit;
    };
    unitConfig = {
      StartLimitBurst = 5;
      StartLimitIntervalSec = 600;
      # Requires=+After= combined with Notify=healthy on workers gives us
      # `depends_on: service_healthy`: the gateway starts only after every worker
      # answers /health, so /get_model_info discovery succeeds.
      After = [ "${cfg.networkName}-network.service" ] ++ workerServices;
      Requires = [ "${cfg.networkName}-network.service" ] ++ workerServices;
    };
  };
in
{
  options.custom.sglang = {
    enable = lib.mkEnableOption "SGLang model serving via Quadlet, fronted by the SGL Model Gateway";

    user = lib.mkOption {
      type = lib.types.str;
      default = "sglang";
      description = "Dedicated system user that owns the rootless SGLang model containers.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/lmsysorg/sglang";
      description = "Container image used for every model worker.";
    };

    tag = lib.mkOption {
      type = lib.types.str;
      example = "latest";
      description = ''
        Default tag of the SGLang image used for models that do not set their own `tag` or `digest`.
        Use the `*-runtime` variants for production deployments.
      '';
    };

    networkName = lib.mkOption {
      type = lib.types.str;
      default = "sglang";
      description = ''
        Name of the shared rootless podman network that joins every container.
        Containers reach each other via container-DNS (e.g. `sglang-<model>:30000`),
        so no host-side port forwarding is needed for inter-container traffic.
      '';
    };

    workerPort = lib.mkOption {
      type = lib.types.port;
      default = 30000;
      description = ''
        Internal port that every model worker binds to inside the shared network.
        Not exposed to the host; the gateway is the only container that publishes ports.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/sglang";
      description = ''
        Home directory of the `sglang` user.
        Used by rootless podman for container storage (`~/.local/share/containers`).
      '';
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/sglang";
      description = "Host directory bind-mounted as the Hugging Face cache for every worker.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        SGLANG_ENABLE_SPEC_V2 = "1";
      };
      description = ''
        Environment variables set on every model worker container.
        Merged with `custom.sglang.models.<name>.environment`; per-model entries take precedence.
      '';
    };

    modelSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        kv-cache-dtype = "fp4_e2m1";
        max-running-requests = 2;
      };
      description = ''
        CLI flags forwarded to `sglang serve` for every worker.
        Rendered via `lib.cli.toCommandLineShellGNU`; entries with `false` or `null` are omitted.
        Merged with `custom.sglang.models.<name>.settings`; per-model entries take precedence.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/sglang/.env";
      description = ''
        File in `KEY=VALUE` format forwarded to every worker via `--env-file`.
        Use for secrets managed by sops-nix/agenix, e.g. a file containing `HF_TOKEN=<token>`.
        Loaded before `custom.sglang.models.<name>.environmentFile`, so per-model files override.
        Must be readable by the `sglang` user.
      '';
    };

    startupOrdering = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to chain enabled model services by alphabetical name during startup.
        SGLang reserves `mem-fraction-static` of total GPU memory at boot; without
        ordering, two workers booting on the same GPU each see the device as fully
        free and race to claim their share, leading to OOM. Disable only when each
        model has its own dedicated GPU (`gpus = [ N ]`).
      '';
    };

    openFilesLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1048576;
      description = ''
        File descriptor limit (`LimitNOFILE`) applied to every SGLang systemd unit.
        Containers copy their ulimits from the host process via `--ulimit host`,
        so this value flows through to the SGLang server inside each container.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule modelOpts);
      default = { };
      example = lib.literalExpression ''
        {
          "qwen3-8b" = {
            model = "Qwen/Qwen3-8B";
            settings = {
              reasoning-parser = "qwen3";
              tool-call-parser = "qwen3_coder";
              mem-fraction-static = 0.6;
              cuda-graph-max-bs = 4;
            };
          };
        }
      '';
      description = ''
        Models to serve.
        Each entry produces one rootless quadlet container; the attribute name doubles as the
        `model_id` advertised via `--served-model-name` and surfaced through the gateway as the
        OpenAI `model` field.
      '';
    };

    gateway = {
      enable = lib.mkEnableOption "the SGL Model Gateway in front of the workers" // {
        default = true;
      };

      image = lib.mkOption {
        type = lib.types.str;
        default = "docker.io/lmsysorg/sgl-model-gateway";
        description = "Container image used for the gateway.";
      };

      tag = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "latest";
        description = "Default tag of the gateway image. Mutually exclusive with `digest`.";
      };

      digest = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Immutable digest of the gateway image. Mutually exclusive with `tag`.";
      };

      bindAddress = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = ''
          Host address the gateway publishes its ports to.
          Defaults to the loopback so external clients must go through Caddy / llmhop.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 30000;
        description = ''
          Port the gateway listens on; used for both the in-container bind and the host publish.
        '';
      };

      enableMetrics = lib.mkEnableOption "Prometheus metrics on the gateway" // {
        default = true;
      };

      metricsPort = lib.mkOption {
        type = lib.types.port;
        default = 29000;
        description = ''
          Port the gateway exposes Prometheus metrics on; used for both bind and publish.
          Ignored when `enableMetrics` is false.
        '';
      };

      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Additional environment variables set on the gateway container.";
      };

      environmentFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/etc/sglang/gateway.env";
        description = ''
          File in `KEY=VALUE` format forwarded to the gateway via `--env-file`.
          Use for secrets like API keys; the gateway's `--api-key` flag may also be passed via
          `settings` if the value is non-secret.
        '';
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = { };
        example = {
          api-key = "secret";
          tls-cert-path = "/etc/sglang/tls/server.crt";
        };
        description = ''
          Additional CLI flags forwarded to `sgl-model-gateway`.
          Rendered via `lib.cli.toCommandLineShellGNU`; entries with `false` or `null` are omitted.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.custom.enableNvidia;
        message = "custom.sglang requires custom.enableNvidia (CDI provides GPU access).";
      }
      {
        assertion = config.virtualisation.quadlet.enable;
        message = "custom.sglang requires virtualisation.quadlet.enable.";
      }
    ];

    # The gateway shares this user with the workers so it joins the same rootless
    # podman network — no host port forwards needed between gateway and workers.
    users.users.${cfg.user} = {
      description = "SGLang User";
      isSystemUser = true;
      uid = 504;
      group = cfg.user;
      home = cfg.dataDir;
      # Real shell so the `sglang` helper (no args) can drop into an interactive
      # session via machinectl. No password is set, so SSH/console login is still impossible.
      shell = config.users.defaultUserShell;
      # Required for `journalctl --user` inside a `machinectl shell` session.
      extraGroups = [ "systemd-journal" ];
      linger = true;
      subUidRanges = [
        {
          startUid = 400000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 400000;
          count = 65536;
        }
      ];
    };
    users.groups.${cfg.user}.gid = config.users.users.${cfg.user}.uid;

    systemd.tmpfiles.settings."10-sglang" = {
      ${cfg.dataDir}.d = {
        user = cfg.user;
        group = cfg.user;
        mode = "0700";
      };
      ${cfg.cacheDir}.d = {
        user = cfg.user;
        group = cfg.user;
        mode = "0700";
      };
    };

    virtualisation.quadlet = {
      networks.${cfg.networkName} = {
        uid = config.users.users.${cfg.user}.uid;
        networkConfig = {
          NetworkName = cfg.networkName;
          DisableDNS = false;
        };
      };

      containers = lib.listToAttrs (
        (lib.imap0 mkModelContainer models) ++ lib.optional cfg.gateway.enable mkGatewayContainer
      );
    };

    # Drop into a shell or run a command as the `sglang` user; inside, standard
    # tools work unmodified (e.g. `sglang systemctl --user status sglang-<model>`).
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "sglang";
        text = ''
          if [ "$#" -eq 0 ]; then
            echo "Entering the sglang user shell. Useful commands:"
            echo "  systemctl --user status sglang-<model>    # service state"
            echo "  journalctl --user -u sglang-<model> -f    # tail logs"
            echo "  podman ps                                 # list containers"
            echo "  exit                                      # back to host"
            exec sudo machinectl --quiet shell ${cfg.user}@.host
          fi
          exec sudo machinectl --quiet shell ${cfg.user}@.host /usr/bin/env "$@"
        '';
      })
    ];
  };
}
