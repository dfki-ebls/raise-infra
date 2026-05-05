{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.dex;

  opensslExe = lib.getExe' pkgs.openssl "openssl";
in
{
  options.custom.dex.sharedSecrets = lib.mkOption {
    default = { };
    description = ''
      Secrets generated once on first boot and shared between dex and a
      downstream consumer. Each entry produces a single random base64
      value, written to:
        - dex's environment file under `dexVar` (match this with the
          corresponding static client's `secretEnv`),
        - `file` under `var` so the consumer reads the same value via its
          own `EnvironmentFile`.

      Adding entries after first boot is safe — only secrets missing from
      dex's environment file are regenerated, existing ones are left alone.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          dexVar = lib.mkOption {
            type = lib.types.str;
            description = "Env-var name written into dex's environment file.";
          };
          file = lib.mkOption {
            # `str` rather than `path` so the absolute runtime path isn't
            # treated as a /nix/store import when interpolated into the
            # bootstrap script.
            type = lib.types.str;
            description = "Absolute path to the consumer's `KEY=VALUE` env file. Created if missing.";
          };
          var = lib.mkOption {
            type = lib.types.str;
            description = "Env-var name written into `file`.";
          };
        };
      }
    );
  };

  config = lib.mkIf config.services.dex.enable {
    systemd.services.dex-generate-secrets = {
      description = "Generate Dex and shared client secrets if missing";
      wantedBy = [ "dex.service" ];
      before = [ "dex.service" ];
      partOf = [ "dex.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        # Ephemeral tmpfs dir for the bootstrap password; gone on reboot.
        RuntimeDirectory = "dex-bootstrap";
        RuntimeDirectoryMode = "0700";
      };
      script = ''
        set -euo pipefail
        umask 077

        install -d -m 755 /etc/dex
        touch /etc/dex/config.yaml
        touch /etc/dex/dex.env

        if ! grep -q '^DEX_ADMIN_HASH=' /etc/dex/dex.env; then
          password=$(${opensslExe} rand -base64 24)
          # mkpasswd (whois 5.6.6) requires `=` for long options; with spaces it
          # silently ignores the value, prints the method list, and exits 0.
          hash=$(echo -n "$password" | ${lib.getExe pkgs.mkpasswd} --method=bcrypt --rounds=14 --stdin)

          if [ "''${#hash}" -ne 60 ]; then
            echo "ERROR: bcrypt hash has unexpected length ''${#hash} (expected 60)" >&2
            exit 1
          fi

          echo "DEX_ADMIN_HASH=$hash" >> /etc/dex/dex.env
          echo "$password" > /run/dex-bootstrap/admin-password
        fi

        ${lib.concatMapStringsSep "\n" (entry: ''
          if ! grep -q '^${entry.dexVar}=' /etc/dex/dex.env; then
            secret=$(${opensslExe} rand -base64 33 | tr -d '\n')
            echo "${entry.dexVar}=$secret" >> /etc/dex/dex.env
            install -d -m 755 ${lib.dirOf entry.file}
            echo "${entry.var}=$secret" >> ${entry.file}
          fi
        '') (lib.attrValues cfg.sharedSecrets)}
      '';
    };
  };
}
