{
  lib,
  config,
  ...
}:
let
  cfg = config.custom.vllm;

  modelOpts =
    { name, ... }:
    {
      options = {
        enable = lib.mkEnableOption "serving of model ${name}";
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
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "--tensor-parallel-size"
            "2"
            "--max-model-len"
            "32768"
          ];
          description = "Additional CLI flags forwarded to `vllm serve`.";
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
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Extra environment variables passed to the container.";
        };
        environmentFile = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [ ];
          description = ''
            Files in `KEY=VALUE` format passed to the container via `--env-file`.
            Use for secrets managed by sops-nix/agenix, e.g. a file containing `HF_TOKEN=<token>`
            to access gated Hugging Face repositories.
            Files must be readable by the `vllm` user.
          '';
        };
      };
    };

  models = lib.attrValues cfg.models;

  cdiDevices =
    model:
    if model.gpus == "all" then
      [ "nvidia.com/gpu=all" ]
    else
      map (i: "nvidia.com/gpu=${toString i}") model.gpus;

  mkContainer =
    model:
    lib.nameValuePair "vllm-${model.name}" {
      uid = config.users.users.${cfg.user}.uid;
      containerConfig = {
        Image = cfg.image;
        PublishPort = [ "127.0.0.1:${toString model.port}:8000" ];
        AddDevice = cdiDevices model;
        Volume = [ "${cfg.cacheDir}:/root/.cache/huggingface" ];
        Environment = model.environment;
        EnvironmentFile = model.environmentFile;
        ShmSize = model.shmSize;
        NoNewPrivileges = true;
        Exec = lib.escapeShellArgs (
          [
            model.model
            "--served-model-name"
            model.name
            "--host"
            "0.0.0.0"
            "--port"
            "8000"
          ]
          ++ model.extraArgs
        );
      };
      serviceConfig = {
        TimeoutStartSec = 3600;
        RestartSec = 30;
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
      default = "docker.io/vllm/vllm-openai:latest";
      description = "Container image used for every model.";
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
            extraArgs = [ "--max-model-len" "8192" ];
          };
        }
      '';
      description = ''
        Models to serve.
        Each entry produces one rootless quadlet container; the attribute name is the routing key.
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
        assertion = lib.length (lib.unique (map (model: model.port) models)) == lib.length models;
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
    users.groups.${cfg.user}.gid = 503;

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

    virtualisation.quadlet.containers = lib.listToAttrs (map mkContainer models);
  };
}
