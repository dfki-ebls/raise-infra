{
  lib,
  config,
  ...
}:
let
  cfg = config.services.llmhop.vllm;

  llmhopLib = import ./_llmhop-lib.nix { inherit lib; };
  inherit (llmhopLib) enabledModels flipBoolFlags;
  inherit (llmhopLib.quadlet)
    mkConfig
    mkContainerArgs
    mkModelSubmodule
    mkOptions
    mkWorker
    ;

  # vLLM auto-generates argparse from dataclass fields and emits
  # `BooleanOptionalAction` for every `bool`-typed option, so the paired
  # `--key` / `--no-key` form is the norm. `flipBoolFlags` leverages that:
  # `key = false` renders as `--no-key`. A small set of manual `store_true`
  # flags (`--headless`, `--grpc`, `--disable-log-stats`,
  # `--aggregate-engine-logging`) do NOT have a `--no-X` counterpart — for
  # those, simply omit the flag instead of writing `... = false`. The `=` form
  # keeps the rendered command a single shell-escaped string for Quadlet `Exec=`.
  renderArgs =
    attrs:
    lib.cli.toCommandLineShell (name: {
      option = "--${name}";
      sep = "=";
      explicitBool = false;
    }) (flipBoolFlags attrs);

  # Internal port every worker binds to inside its container.
  workerPort = 8000;

  # Sort by port so the After= chain is deterministic across rebuilds.
  models = lib.pipe (enabledModels cfg) [
    lib.attrValues
    (lib.sort (a: b: a.port < b.port))
  ];

  mkContainer =
    i: model:
    lib.nameValuePair "vllm-${model.name}" (mkWorker {
      inherit (cfg) openFilesLimit;
      healthPort = workerPort;
      containerConfig =
        (mkContainerArgs {
          backend = "vllm";
          inherit cfg model;
        })
        // {
          PublishPort = [ "127.0.0.1:${toString model.port}:${toString workerPort}" ];
          Exec = "${lib.escapeShellArg model.model} ${
            renderArgs (
              {
                served-model-name = model.name;
                host = "0.0.0.0";
                port = workerPort;
              }
              // cfg.modelSettings
              // model.settings
            )
          }";
        };
      # Chain ascending so each worker finishes GPU-memory profiling before the next starts.
      unitConfig = {
        After =
          lib.optional (cfg.startupOrdering && i > 0)
            "${
              config.virtualisation.quadlet.containers."vllm-${(lib.elemAt models (i - 1)).name}".serviceName
            }.service";
      };
    });
in
{
  options.services.llmhop.vllm =
    mkOptions {
      backend = "vllm";
      inherit cfg;
      defaultImage = "docker.io/vllm/vllm-openai";
      defaultCacheDir = "/var/cache/vllm";
      tagExample = "v0.11.0";
    }
    // {
      enable = lib.mkEnableOption "vLLM model serving via Quadlet, fronted by llmhop";

      models = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            imports = [ (mkModelSubmodule { backend = "vllm"; }) ];
            options.port = lib.mkOption {
              type = lib.types.port;
              description = ''
                Loopback host port forwarded to the container's vLLM API.
                Must be unique per model.
              '';
            };
          }
        );
        default = { };
        example = lib.literalExpression ''
          {
            "qwen2-5-7b" = {
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
          Each entry produces one quadlet container; the attribute name is the routing key.
          Enabled entries are sorted by ascending `port`.
        '';
      };
    };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (mkConfig {
        backend = "vllm";
        inherit cfg config;
        description = "vLLM User";
      })
      {
        virtualisation.quadlet.containers = lib.listToAttrs (lib.imap0 mkContainer models);
      }
    ]
  );
}
