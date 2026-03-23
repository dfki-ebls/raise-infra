{
  config,
  lib,
  pkgs,
  ...
}:
let
  protocol = if config.custom.enableCertificates then "https" else "http";
in
{
  services.dex = {
    enable = false;
    environmentFile = "/etc/dex/dex.env";
    settings = {
      issuer = "${protocol}://dex.${config.custom.rootDomain}";
      web = {
        http = "127.0.0.1:5556";
        allowedOrigins = [
          "${protocol}://app.${config.custom.rootDomain}"
        ];
      };
      storage = {
        type = "sqlite3";
        config.file = "/var/lib/dex/dex.db";
      };
      oauth2 = {
        skipApprovalScreen = true;
        responseTypes = [ "code" ];
      };
      expiry = {
        idTokens = "10m";
        signingKeys = "6h";
        refreshTokens = {
          validIfNotUsedFor = "168h";
          absoluteLifetime = "720h";
          reuseInterval = "30s";
        };
      };
      enablePasswordDB = true;
      staticPasswords = [
        {
          email = config.custom.admin.mail;
          username = config.custom.admin.login;
          name = config.custom.admin.name;
          preferredUsername = config.custom.admin.login;
          emailVerified = true;
          userID = "admin";
          hashFromEnv = "DEX_ADMIN_HASH";
        }
      ];
      staticClients = [
        {
          id = "app";
          name = "Web Application";
          public = true;
          redirectURIs = [
            "${protocol}://app.${config.custom.rootDomain}/auth/callback"
          ];
        }
      ];
    };
  };

  systemd.services.dex-generate-secrets = lib.mkIf config.services.dex.enable {
    description = "Generate Dex secrets if missing";
    wantedBy = [ "dex.service" ];
    before = [ "dex.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "dex-generate-secrets" ''
        set -euo pipefail

        install -d -m 750 /etc/dex

        touch /etc/dex/config.yaml
        chmod 600 /etc/dex/config.yaml

        if [ -s /etc/dex/dex.env ]; then
          echo "/etc/dex/dex.env already populated, skipping generation"
          exit 0
        fi

        password=$(${lib.getExe' pkgs.openssl "openssl"} rand -base64 24)
        hash=$(echo -n "$password" | ${lib.getExe pkgs.mkpasswd} --method bcrypt --rounds 12 --stdin)

        echo "DEX_ADMIN_HASH=$hash" > /etc/dex/dex.env
        chmod 600 /etc/dex/dex.env

        echo "$password" > /etc/dex/admin-password.txt
        chmod 600 /etc/dex/admin-password.txt
      '';
    };
  };

  systemd.services.dex.serviceConfig = lib.mkIf config.services.dex.enable {
    StateDirectory = "dex";
    LoadCredential = [ "config.yaml:/etc/dex/config.yaml" ];
    ExecStartPre = lib.mkAfter [
      (pkgs.writeShellScript "dex-merge-config" ''
        set -euo pipefail

        if [ ! -s "$CREDENTIALS_DIRECTORY/config.yaml" ]; then
          echo "/etc/dex/config.yaml is empty, skipping merge"
          exit 0
        fi

        ${lib.getExe pkgs.yq-go} eval-all -i \
          'select(fileIndex==0) *+ select(fileIndex==1)' \
          /run/dex/config.yaml "$CREDENTIALS_DIRECTORY/config.yaml"
      '')
    ];
  };

  # Restart Dex when /etc/dex/config.yaml changes (e.g. new users added)
  systemd.paths.etc-dex-config = lib.mkIf config.services.dex.enable {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "/etc/dex/config.yaml";
    unitConfig.Unit = "dex.service";
  };
}
