{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.custom.rauthy;

  opensslExe = lib.getExe' pkgs.openssl "openssl";
in
{
  config = lib.mkIf cfg.enable {
    # Pre-create the secrets dir at boot. The `rauthy-generate-secrets`
    # oneshot runs under `ProtectSystem = "strict"` and bind-mounts
    # `/etc/rauthy` read-write via `ReadWritePaths`; systemd silently
    # ignores missing entries there, so without this rule `/etc` stays
    # read-only inside the namespace on first boot and the script fails
    # to create the env file.
    systemd.tmpfiles.rules = [ "d /etc/rauthy 0755 root root -" ];

    # The ChaCha20Poly1305 encryption keys (`ENC_KEYS`/`ENC_KEY_ACTIVE`)
    # overwrite their TOML equivalents in `[encryption]`, so they could in
    # theory be moved into `settings`. That would serialize the secrets
    # into `/nix/store` (world-readable), which we explicitly want to
    # avoid. Keeping them in this oneshot's root-owned `0600` env file is
    # the only place they don't leak — and the operator never has to
    # generate or manage them by hand.
    systemd.services.rauthy-generate-secrets = {
      description = "Generate Rauthy bootstrap secrets if missing";
      wantedBy = [ "rauthy.service" ];
      before = [ "rauthy.service" ];
      partOf = [ "rauthy.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/etc/rauthy" ];
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
      };
      script = ''
        set -euo pipefail
        umask 077

        touch /etc/rauthy/rauthy.env

        # `encryption.keys` / `encryption.key_active`: ChaCha20Poly1305 key(s)
        # used for encrypting confidential client secrets, sessions, etc.
        # Format is `<id>/<base64-32-bytes>`; the id must match
        # `^[a-zA-Z0-9:_-]{2,20}$` (8 hex chars satisfy that). Multiple keys
        # would be `\n`-separated; a single key is enough at bootstrap, and
        # rotation is a manual operation via the admin UI.
        if ! grep -q '^ENC_KEYS=' /etc/rauthy/rauthy.env; then
          enc_id=$(${opensslExe} rand -hex 4)
          enc_key=$(${opensslExe} rand -base64 32)
          echo "ENC_KEYS=$enc_id/$enc_key" >> /etc/rauthy/rauthy.env
          echo "ENC_KEY_ACTIVE=$enc_id" >> /etc/rauthy/rauthy.env
        fi
      '';
    };
  };
}
