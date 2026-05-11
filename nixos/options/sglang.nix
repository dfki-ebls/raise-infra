{
  lib,
  config,
  ...
}:
let
  cfg = config.services.llmhop.sglang;

  llmhopLib = import ./_llmhop-lib.nix { inherit lib; };
  inherit (llmhopLib) enabledModels resolveImageRef;
  inherit (llmhopLib.quadlet)
    mkConfig
    mkContainerArgs
    mkModelSubmodule
    mkOptions
    mkWorker
    ;

  # SGLang's argparse uses plain `store_true` booleans paired as
  # `--enable-X` / `--disable-X` (only a tiny handful of flags use
  # `BooleanOptionalAction`, so `--no-X` is NOT a reliable form). The Rust
  # SGL Model Gateway uses clap `SetTrue`, which also has no auto-negation.
  # We therefore deliberately do NOT apply `flipBoolFlags` here: `true`
  # collapses to `--key`, `null`/`false` are dropped, and the user picks the
  # matching flag from the explicit pair (e.g. `disable-radix-cache = true`).
  renderArgs =
    attrs:
    lib.cli.toCommandLineShell (name: {
      option = "--${name}";
      sep = "=";
      explicitBool = false;
    }) attrs;

  # Internal port every worker binds to inside its container. Not exposed
  # because the gateway reaches workers through their published host loopback
  # ports rather than through container DNS.
  workerPort = 30000;

  # Sort by port so the After= chain is deterministic across rebuilds.
  models = lib.pipe (enabledModels cfg) [
    lib.attrValues
    (lib.sort (a: b: a.port < b.port))
  ];

  mkContainer =
    i: model:
    lib.nameValuePair "sglang-${model.name}" (mkWorker {
      inherit (cfg) openFilesLimit;
      healthPort = workerPort;
      containerConfig =
        (mkContainerArgs {
          backend = "sglang";
          inherit cfg model;
        })
        // {
          PublishPort = [ "127.0.0.1:${toString model.port}:${toString workerPort}" ];
          # `lmsysorg/sglang`'s default entrypoint isn't the launcher we want.
          # The new `sglang serve` CLI emits a deprecation warning for this path,
          # but the `sglang` console script is missing from the `*-runtime` image
          # and `sglang.cli.main` lacks a `__main__` guard, so `launch_server`
          # remains the only working invocation here.
          Entrypoint = lib.toJSON [
            "sglang"
            "serve"
          ];
          Exec = renderArgs (
            {
              model-path = model.model;
              served-model-name = model.name;
              host = "0.0.0.0";
              port = workerPort;
            }
            // cfg.modelSettings
            // model.settings
          );
        };
      # Chain ascending so each worker finishes GPU-memory profiling before the next starts.
      unitConfig = {
        After =
          lib.optional (cfg.startupOrdering && i > 0)
            "${
              config.virtualisation.quadlet.containers."sglang-${(lib.elemAt models (i - 1)).name}".serviceName
            }.service";
      };
    });

  # The gateway calls /get_model_info on each `worker-urls` entry and uses the worker's
  # `--served-model-name` as the routing key — a fully declarative IGW dispatch table.
  # Running on the host network namespace lets us reuse each worker's published
  # loopback port instead of standing up a dedicated podman network.
  gatewayBaseSettings = {
    host = cfg.gateway.bindAddress;
    port = cfg.gateway.port;
    prometheus-host = if cfg.gateway.enableMetrics then cfg.gateway.bindAddress else null;
    prometheus-port = if cfg.gateway.enableMetrics then cfg.gateway.metricsPort else null;
    enable-igw = true;
  };

  # `--worker-urls` uses argparse `nargs='*'` and must be appended manually so the URLs
  # become separate argv entries; `renderArgs` would shell-escape them into one.
  gatewayExec =
    renderArgs (gatewayBaseSettings // cfg.gateway.settings)
    +
      lib.optionalString (models != [ ])
        " ${lib.escapeShellArgs (
           [ "--worker-urls" ] ++ map (m: "http://127.0.0.1:${toString m.port}") models
         )}";

  workerServices = map (
    m: "${config.virtualisation.quadlet.containers."sglang-${m.name}".serviceName}.service"
  ) models;

  mkGatewayContainer = lib.nameValuePair "sglang-gateway" (mkWorker {
    inherit (cfg) openFilesLimit;
    healthPort = cfg.gateway.port;
    healthStartPeriod = "5m";
    containerConfig = {
      UIDMap = [
        "0:${toString cfg.uid}:1"
        "1:${toString cfg.subUidStart}:${toString cfg.subUidCount}"
      ];
      GIDMap = [
        "0:${toString cfg.gid}:1"
        "1:${toString cfg.subGidStart}:${toString cfg.subGidCount}"
      ];
      Image = resolveImageRef {
        inherit (cfg.gateway) image tag digest;
        defaultTag = "latest";
        label = "services.llmhop.sglang.gateway";
      };
      Pull = if cfg.gateway.digest != null then "missing" else "newer";
      ReadOnly = true;
      # Host networking lets the gateway reach each worker at
      # `127.0.0.1:<model.port>` and binds its own listeners directly on
      # `bindAddress`, so no `PublishPort` is required.
      Network = "host";
      EnvironmentFile = lib.optional (cfg.gateway.environmentFile != null) cfg.gateway.environmentFile;
      Environment = cfg.gateway.environment;
      Exec = gatewayExec;
    };
    # The gateway is a stateless Rust binary — short timing overrides the
    # worker-scale defaults baked into `mkWorker`.
    serviceConfig = {
      TimeoutStartSec = 600;
      RestartSec = 10;
    };
    unitConfig = {
      StartLimitBurst = 5;
      StartLimitIntervalSec = 600;
      # Requires=+After= combined with Notify=healthy on workers gives us
      # `depends_on: service_healthy`: the gateway starts only after every worker
      # answers /health, so /get_model_info discovery succeeds.
      After = workerServices;
      Requires = workerServices;
    };
  });
in
{
  options.services.llmhop.sglang =
    mkOptions {
      backend = "sglang";
      inherit cfg;
      defaultImage = "docker.io/lmsysorg/sglang";
      defaultCacheDir = "/var/cache/sglang";
    }
    // {
      enable = lib.mkEnableOption "SGLang model serving via Quadlet, optionally fronted by the SGL Model Gateway";

      models = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            imports = [ (mkModelSubmodule { backend = "sglang"; }) ];
            options.port = lib.mkOption {
              type = lib.types.port;
              description = ''
                Loopback host port forwarded to the container's SGLang API.
                Must be unique per model and must not collide with `gateway.port` /
                `gateway.metricsPort` when the gateway is enabled.
              '';
            };
          }
        );
        default = { };
        example = lib.literalExpression ''
          {
            "qwen3-8b" = {
              model = "Qwen/Qwen3-8B";
              port = 19001;
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
          Each entry produces one quadlet container; the attribute name is the routing key
          (advertised via `--served-model-name` and surfaced through both llmhop and the
          optional SGL Model Gateway as the OpenAI `model` field).
          Enabled entries are sorted by ascending `port`.
        '';
      };

      gateway = {
        enable = lib.mkEnableOption ''
          the SGL Model Gateway in front of the workers.
          Disabled by default — llmhop already routes between every backend, and the
          gateway is only needed when you want SGLang's IGW dispatch features
          (custom routing, prefix caching across workers, etc.)
        '';

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
            Host address the gateway binds its listeners to.
            Defaults to the loopback so external clients must go through Caddy / llmhop.
          '';
        };

        port = lib.mkOption {
          type = lib.types.port;
          description = "Host port the gateway listens on.";
        };

        enableMetrics = lib.mkEnableOption "Prometheus metrics on the gateway" // {
          default = true;
        };

        metricsPort = lib.mkOption {
          type = lib.types.port;
          default = 29000;
          description = ''
            Host port the gateway exposes Prometheus metrics on.
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
            `true` collapses to `--<key>`; `null` and `false` are dropped (write
            the negated key explicitly when the upstream CLI registers one).
          '';
        };
      };
    };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (mkConfig {
        backend = "sglang";
        inherit cfg config;
        description = "SGLang User";
        extras =
          lib.optionalAttrs cfg.gateway.enable { gateway = cfg.gateway.port; }
          // lib.optionalAttrs (cfg.gateway.enable && cfg.gateway.enableMetrics) {
            gateway-metrics = cfg.gateway.metricsPort;
          };
        portsMessage = "services.llmhop.sglang: each model `port` must be unique and must not collide with `gateway.port` or `gateway.metricsPort`.";
      })
      {
        virtualisation.quadlet.containers = lib.listToAttrs (
          (lib.imap0 mkContainer models) ++ lib.optional cfg.gateway.enable mkGatewayContainer
        );
      }
    ]
  );
}
