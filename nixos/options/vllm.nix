{
  lib,
  config,
  pkgs,
  ...
}:
let
  cfg = config.custom.vllm;

  mkArgs =
    attrs:
    lib.cli.toCommandLineShellGNU { } (
      lib.mapAttrs' (
        k: v: if v == false then lib.nameValuePair "no-${k}" true else lib.nameValuePair k v
      ) attrs
    );

  # vLLM doesn't strictly need DNS-safe names (no inter-container DNS), but we mirror
  # sglang's constraint so unit names stay simple and the two modules read identically.
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
            (`vllm-<name>`) and as the routing name exposed by llmhop (clients select
            the backend by sending this value in the OpenAI `model` field).

            Defaults to the attribute key, so the key itself must be a DNS label
            (starts with an alphanumeric, then alphanumerics or hyphens; no dots).
          '';
        };
        model = lib.mkOption {
          type = lib.types.str;
          example = "Qwen/Qwen2.5-7B-Instruct";
          description = "Hugging Face repo id (or local path) passed to vLLM as the positional model argument.";
        };
        tag = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Tag of the container image used for this model.
            Mutually exclusive with `digest`.
          '';
        };
        digest = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "sha256:a73fb0b9046fee099f7c1829d2548e6cc1740f4c2776a6855fa659ae5d0deb49";
          description = ''
            Immutable digest of the container image (e.g. `sha256:…`).
            Mutually exclusive with `tag`.
          '';
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = "Loopback host port forwarded to the container's vLLM API. Must be unique per model.";
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
            tensor-parallel-size = 2;
            max-model-len = 32768;
          };
          description = ''
            Additional CLI flags forwarded to `vllm serve`.
            Rendered via `lib.cli.toCommandLineShellGNU`.
            Merged with `custom.vllm.modelSettings`; these entries take precedence.
          '';
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          example = {
            VLLM_FLASHINFER_MOE_BACKEND = "throughput";
          };
          description = ''
            Additional environment variables set on the container.
            Merged with `custom.vllm.environment`; these entries take precedence.
          '';
        };
        environmentFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          example = "/etc/vllm/qwen.env";
          description = ''
            File in `KEY=VALUE` format forwarded to this model's container via `--env-file`.
            Loaded after `custom.vllm.environmentFile`, so its entries override global ones.
            Must be readable by the `vllm` user.
          '';
        };
        shmSize = lib.mkOption {
          type = lib.types.str;
          default = "2g";
          example = "16g";
          description = ''
            Size of the container's private `/dev/shm` tmpfs.
            PyTorch uses shared memory for NCCL/tensor-parallel inference; upstream requires
            either this or `--ipc=host`.
            A private tmpfs is preferred for isolation: raise the value for larger models or
            higher tensor-parallel sizes (upstream suggests `16g` for TP=8).
          '';
        };
      };
    };

  # Sort by port so the After= chain below is deterministic across rebuilds.
  models = lib.pipe cfg.models [
    lib.attrValues
    (lib.filter (model: model.enable))
    (lib.sort (a: b: a.port < b.port))
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
      throw "custom.vllm.models.${model.name}: `tag` and `digest` are mutually exclusive."
    else if model.digest != null then
      "${cfg.image}@${model.digest}"
    else
      "${cfg.image}:${if model.tag != null then model.tag else cfg.tag}";

  mkContainer =
    i: model:
    lib.nameValuePair "vllm-${model.name}" {
      uid = config.users.users.${cfg.user}.uid;
      # Rootfs stays writable so torch's compile cache and vLLM's scratch files don't fail.
      containerConfig = {
        Image = imageRef model;
        Pull = if model.digest != null then "missing" else "newer";
        PublishPort = [ "127.0.0.1:${toString model.port}:8000" ];
        AddDevice = cdiDevices model;
        Volume = [ "${cfg.cacheDir}:/root/.cache/huggingface" ];
        EnvironmentFile =
          lib.optional (cfg.environmentFile != null) cfg.environmentFile
          ++ lib.optional (model.environmentFile != null) model.environmentFile;
        Environment = cfg.environment // model.environment;
        ShmSize = model.shmSize;
        Ulimit = "host";
        NoNewPrivileges = true;
        DropCapability = "all";
        Notify = "healthy";
        HealthCmd = "curl --fail --silent --show-error http://localhost:8000/health";
        HealthStartPeriod = "30m";
        HealthInterval = "10s";
        HealthTimeout = "5s";
        Exec = "${lib.escapeShellArg model.model} ${
          mkArgs (
            {
              served-model-name = model.name;
              host = "0.0.0.0";
              port = 8000;
            }
            // cfg.modelSettings
            // model.settings
          )
        }";
      };
      serviceConfig = {
        TimeoutStartSec = 3600;
        RestartSec = 30;
        LimitNOFILE = cfg.openFilesLimit;
      };
      # Chain ascending so each worker finishes GPU-memory profiling before the next starts.
      unitConfig = {
        StartLimitBurst = 3;
        StartLimitIntervalSec = 3600;
        After =
          lib.optional (cfg.startupOrdering && i > 0)
            "vllm-${(lib.elemAt models (i - 1)).name}.service";
      };
    };
in
{
  options.custom.vllm = {
    enable = lib.mkEnableOption "vLLM model serving via Quadlet, fronted by llmhop";

    user = lib.mkOption {
      type = lib.types.str;
      default = "vllm";
      description = "Dedicated system user that owns the rootless vLLM containers.";
    };

    image = lib.mkOption {
      type = lib.types.str;
      default = "docker.io/vllm/vllm-openai";
      description = "Container image used for every model.";
    };

    tag = lib.mkOption {
      type = lib.types.str;
      example = "v0.11.0";
      description = ''
        Default tag of the container image used for models that do not set their own `tag` or `digest`.
        Can be overridden per model via `custom.vllm.models.<name>.tag` or `.digest`.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/vllm";
      description = ''
        Home directory of the `vllm` user.
        Used by rootless podman for container storage (`~/.local/share/containers`).
      '';
    };

    cacheDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/cache/vllm";
      description = "Host directory bind-mounted as the Hugging Face cache.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        VLLM_FLASHINFER_MOE_BACKEND = "throughput";
      };
      description = ''
        Environment variables set on every container.
        Merged with `custom.vllm.models.<name>.environment`; per-model entries take precedence.
      '';
    };

    modelSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      example = {
        kv-cache-dtype = "fp8";
        max-num-seqs = 2;
      };
      description = ''
        CLI flags forwarded to `vllm serve` for every model.
        Rendered via `lib.cli.toCommandLineShellGNU`.
        Merged with `custom.vllm.models.<name>.settings`; per-model entries take precedence.
      '';
    };

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/vllm/.env";
      description = ''
        File in `KEY=VALUE` format forwarded to every container via `--env-file`.
        Use for secrets managed by sops-nix/agenix, e.g. a file containing
        `HF_TOKEN=<token>` to access gated Hugging Face repositories.
        Loaded before `custom.vllm.models.<name>.environmentFile`, so per-model files override these entries.
        Must be readable by the `vllm` user.
      '';
    };

    startupOrdering = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to chain enabled model services by ascending `port` during startup.
        This reduces GPU-memory profiling races when models rely on `gpu-memory-utilization`.
      '';
    };

    openFilesLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1048576;
      description = ''
        File descriptor limit (`LimitNOFILE`) applied to every vLLM systemd unit.
        Containers copy their ulimits from the host process via `--ulimit host`,
        so this value flows through to the vLLM server inside each container.
        Increase this if vLLM logs `accept: Too many open files` under concurrent load.
      '';
    };

    models = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule modelOpts);
      default = { };
      example = lib.literalExpression ''
        {
          "qwen2.5-7b" = {
            model = "Qwen/Qwen2.5-7B-Instruct";
            port = 18001;
          };
          "llama-3-8b" = {
            model = "meta-llama/Meta-Llama-3-8B-Instruct";
            port = 18002;
            settings.max-model-len = 8192;
          };
        }
      '';
      description = ''
        Models to serve.
        Each entry produces one rootless quadlet container; the attribute name is the routing key.
        Enabled entries are sorted by ascending `port`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.custom.enableNvidia;
        message = "custom.vllm requires custom.enableNvidia (CDI provides GPU access).";
      }
      {
        assertion = config.virtualisation.quadlet.enable;
        message = "custom.vllm requires virtualisation.quadlet.enable.";
      }
      {
        assertion =
          lib.pipe models [
            (map (model: model.port))
            lib.unique
            lib.length
          ] == lib.length models;
        message = "custom.vllm.models: each model must use a unique `port`.";
      }
    ];

    users.users.${cfg.user} = {
      description = "vLLM User";
      isSystemUser = true;
      uid = 503;
      group = cfg.user;
      home = cfg.dataDir;
      # Real shell so the `vllm` helper (no args) can drop into an interactive
      # session via machinectl. No password is set, so SSH/console login is still impossible.
      shell = config.users.defaultUserShell;
      # Required for `journalctl --user` inside a `machinectl shell` session.
      extraGroups = [ "systemd-journal" ];
      linger = true;
      subUidRanges = [
        {
          startUid = 300000;
          count = 65536;
        }
      ];
      subGidRanges = [
        {
          startGid = 300000;
          count = 65536;
        }
      ];
    };
    users.groups.${cfg.user}.gid = config.users.users.${cfg.user}.uid;

    systemd.tmpfiles.settings."10-vllm" = {
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

    virtualisation.quadlet.containers = lib.listToAttrs (lib.imap0 mkContainer models);

    # Drop into a shell or run a command as the `vllm` user; inside, standard
    # tools work unmodified (e.g. `vllm systemctl --user status vllm-<model>`).
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "vllm";
        text = ''
          if [ "$#" -eq 0 ]; then
            echo "Entering the vllm user shell. Useful commands:"
            echo "  systemctl --user status vllm-<model>    # service state"
            echo "  journalctl --user -u vllm-<model> -f    # tail logs"
            echo "  podman ps                               # list containers"
            echo "  exit                                    # back to host"
            exec sudo machinectl --quiet shell ${cfg.user}@.host
          fi
          exec sudo machinectl --quiet shell ${cfg.user}@.host /usr/bin/env "$@"
        '';
      })
    ];
  };
}
