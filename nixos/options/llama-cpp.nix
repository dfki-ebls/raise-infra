{
  lib,
  config,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.services.llmhop.llama-cpp;

  llmhopLib = import ./_llmhop-lib.nix { inherit lib; };
  inherit (llmhopLib) enabledModels flipBoolFlags;
  inherit (llmhopLib.systemd)
    mkConfig
    mkModelSubmodule
    mkOptions
    mkWorker
    ;

  # llama-server has a custom parser: `--key=value` is rejected (only space-separated
  # `--key value`), and `handler_bool`-registered options come in explicitly-paired
  # forms (e.g. `--mmap` / `--no-mmap`, `--jinja` / `--no-jinja`). `flipBoolFlags`
  # makes `key = false` render as `--no-key`, so users can write either
  # `mmap = false` or `no-mmap = true`. Not every boolean-typed switch is paired,
  # though: single-direction flags like `--verbose` / `--interactive` have no
  # `--no-X` counterpart, and tri-state options like `--flash-attn` take an
  # `on|off|auto` string — for those, set the positive form only (or pass the
  # string value) instead of `... = false`. Rendered as a list of separate argv
  # tokens for systemd `ExecStart=` (the unit passes them through
  # `utils.escapeSystemdExecArgs`).
  renderArgs =
    attrs:
    lib.cli.toCommandLine (name: {
      option = "--${name}";
      sep = null;
      explicitBool = false;
    }) (flipBoolFlags attrs);

  mkService =
    model:
    let
      subdir = "llama-cpp/${model.name}";
    in
    lib.nameValuePair "llama-cpp-${model.name}" (
      {
        description = "llama.cpp server for ${model.name}";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        environment = {
          LLAMA_CACHE = "/var/cache/${subdir}";
        }
        // cfg.environment
        // model.environment;
      }
      // mkWorker {
        inherit (cfg) openFilesLimit;
        serviceConfig = {
          Type = "idle";
          KillSignal = "SIGINT";
          Restart = "on-failure";
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
            ++ renderArgs (
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

          # llama-server listens on its own port; bind() to anything else is denied
          # by `SocketBindDeny = "any"` from the baked-in systemd hardening.
          SocketBindAllow = "tcp:${toString model.port}";
        };
      }
    );
in
{
  options.services.llmhop.llama-cpp = mkOptions { backend = "llama-cpp"; } // {
    enable = lib.mkEnableOption "llama.cpp model serving via systemd, fronted by llmhop";

    package = lib.mkPackageOption pkgs "llama-cpp" { };

    models = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          imports = [ (mkModelSubmodule { backend = "llama-cpp"; }) ];
          options.port = lib.mkOption {
            type = lib.types.port;
            description = ''
              Loopback host port that llama-server binds to. Must be unique per
              enabled model; the gateway (llmhop) reaches each backend at
              `http://127.0.0.1:<port>`.
            '';
          };
        }
      );
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
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      (mkConfig {
        backend = "llama-cpp";
        inherit cfg;
      })
      {
        systemd.services = lib.mapAttrs' (_: mkService) (enabledModels cfg);
      }
    ]
  );
}
