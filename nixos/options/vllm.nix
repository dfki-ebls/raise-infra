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

  modelOpts =
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "serving of model ${name}" // {
          default = true;
        };
        name = lib.mkOption {
          type = lib.types.str;
          default = name;
          description = ''
            Routing name exposed by llmhop.
            Clients select the backend by sending this value in the OpenAI `model` field.
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
        extraArgs = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          example = {
            tensor-parallel-size = 2;
            max-model-len = 32768;
          };
          description = ''
            Additional CLI flags forwarded to `vllm serve`.
            Rendered via `lib.cli.toCommandLineShellGNU`.
            Set `kv-cache-memory-bytes` manually to avoid vLLM's startup memory profiling and make startup ordering unnecessary.
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
            Merged with `custom.vllm.environmentFile`; these entries take precedence.
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

  # Keep enabled models in ascending port order so optional startup chaining is explicit and deterministic.
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
      containerConfig = {
        Image = imageRef model;
        Pull = if model.digest != null then "missing" else "newer";
        PublishPort = [ "127.0.0.1:${toString model.port}:8000" ];
        AddDevice = cdiDevices model;
        Volume = [ "${cfg.cacheDir}:/root/.cache/huggingface" ];
        EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
        Environment = lib.mapAttrsToList (k: v: "${k}=${v}") model.environment;
        ShmSize = model.shmSize;
        NoNewPrivileges = true;
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
            // model.extraArgs
          )
        }";
      };
      serviceConfig = {
        TimeoutStartSec = 3600;
        RestartSec = 30;
      };
      # Chain units via After= by ascending port so GPU-profiling phases don't overlap during startup.
      # Notify=healthy makes each unit go "active" only once vLLM answers /health.
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

    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/etc/vllm/.env";
      description = ''
        File in `KEY=VALUE` format forwarded to every container via `--env-file`.
        Use for secrets managed by sops-nix/agenix, e.g. a file containing
        `HF_TOKEN=<token>` to access gated Hugging Face repositories.
        Must be readable by the `vllm` user.
      '';
    };

    startupOrdering = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to chain enabled model services by ascending `port` during startup.
        This reduces GPU-memory profiling races when models rely on `gpu-memory-utilization`.
        Disable this when you set `extraArgs.kv-cache-memory-bytes` manually or otherwise avoid profiling-time contention.
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
            extraArgs.max-model-len = 8192;
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

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "vllm-systemctl";
        text = ''
          if [ "$#" -lt 2 ]; then
            echo "Usage: $0 <action> <model> [args...]"
            exit 1
          fi
          action="$1"
          shift
          model="$1"
          shift
          sudo systemctl --user --machine=${cfg.user}@.host "$action" "vllm-$model.service" "$@"
        '';
      })
      (pkgs.writeShellApplication {
        name = "vllm-podman";
        text = ''
          sudo machinectl shell ${cfg.user}@.host ${lib.getExe config.virtualisation.podman.package} "$@"
        '';
      })
      (pkgs.writeShellApplication {
        name = "vllm-journalctl";
        text = ''
          if [ "$#" -lt 1 ]; then
            echo "Usage: $0 <model> [args...]"
            exit 1
          fi
          model="$1"
          shift
          sudo journalctl _UID="${
            toString config.users.users.${cfg.user}.uid
          }" _SYSTEMD_USER_UNIT="vllm-$model.service" "$@"
        '';
      })
    ];
  };
}
