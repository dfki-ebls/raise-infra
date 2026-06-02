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
    # `ReadWritePaths` needs the target directory to exist.
    systemd.tmpfiles.rules = [ "d /etc/rauthy 0755 root root -" ];

    # Keep generated secrets out of the Nix store.
    systemd.services.rauthy-generate-secrets = {
      description = "Generate Rauthy bootstrap secrets if missing";
      requiredBy = [ "rauthy.service" ];
      before = [ "rauthy.service" ];
      partOf = [ "rauthy.service" ];
      serviceConfig = {
        Type = "oneshot";
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

        # Rauthy encryption keys.
        if ! grep -q '^ENC_KEYS=' /etc/rauthy/rauthy.env; then
          enc_id=$(${opensslExe} rand -hex 4)
          enc_key=$(${opensslExe} rand -base64 32)
          echo "ENC_KEYS=$enc_id/$enc_key" >> /etc/rauthy/rauthy.env
          echo "ENC_KEY_ACTIVE=$enc_id" >> /etc/rauthy/rauthy.env
        fi

        # Hiqlite authentication secrets.
        if ! grep -q '^HQL_SECRET_RAFT=' /etc/rauthy/rauthy.env; then
          echo "HQL_SECRET_RAFT=$(${opensslExe} rand -hex 24)" >> /etc/rauthy/rauthy.env
        fi

        if ! grep -q '^HQL_SECRET_API=' /etc/rauthy/rauthy.env; then
          echo "HQL_SECRET_API=$(${opensslExe} rand -hex 24)" >> /etc/rauthy/rauthy.env
        fi
      '';
    };
  };
}
