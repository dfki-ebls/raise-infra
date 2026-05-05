{
  config,
  lib,
  pkgs,
  caddyHelpers,
  ...
}:
{
  services.dex = {
    enable = true;
    environmentFile = "/etc/dex/dex.env";
    settings = {
      issuer = caddyHelpers.mkHost "dex.${config.custom.rootDomain}";
      web.http = "127.0.0.1:5556";
      storage = {
        type = "sqlite3";
        config.file = "/var/lib/dex/dex.db";
      };
      oauth2 = {
        # Global: suppresses the consent screen for every client. Safe while
        # the only static client is first-party; revisit if a third-party
        # client is ever added (Dex has no per-client override for this).
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
          hashFromEnv = "DEX_ADMIN_HASH";
          # Opaque, stable OIDC `sub` generated via `uuidgen`.
          # Apps key user data on this value, so do not change it.
          userID = "38b0b104-f0da-4103-88d5-ce117a213d1d";
        }
      ];
    };
  };

  systemd.services.dex-generate-secrets = lib.mkIf config.services.dex.enable {
    description = "Generate Dex secrets if missing";
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

      if [ -s /etc/dex/dex.env ]; then
        echo "/etc/dex/dex.env already populated, skipping generation"
        exit 0
      fi

      password=$(${lib.getExe' pkgs.openssl "openssl"} rand -base64 24)
      # mkpasswd (whois 5.6.6) requires `=` for long options; with spaces it
      # silently ignores the value, prints the method list, and exits 0.
      hash=$(echo -n "$password" | ${lib.getExe pkgs.mkpasswd} --method=bcrypt --rounds=14 --stdin)

      if [ "''${#hash}" -ne 60 ]; then
        echo "ERROR: bcrypt hash has unexpected length ''${#hash} (expected 60)" >&2
        exit 1
      fi

      echo "DEX_ADMIN_HASH=$hash" > /etc/dex/dex.env

      echo "$password" > /run/dex-bootstrap/admin-password
    '';
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

  # Restart Dex when /etc/dex/config.yaml changes (e.g. new users added).
  # systemd.path can only *activate* a unit, so the matching .service is a
  # oneshot that issues the restart on dex.service itself.
  systemd.paths.dex-restart = lib.mkIf config.services.dex.enable {
    description = "Watch /etc/dex/config.yaml for changes";
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "/etc/dex/config.yaml";
  };

  systemd.services.dex-restart = lib.mkIf config.services.dex.enable {
    description = "Restart Dex when its config overlay changes";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${lib.getExe' pkgs.systemd "systemctl"} try-restart dex.service";
    };
  };

  services.caddy.virtualHosts.dex = lib.mkIf config.services.dex.enable {
    hostName = config.services.dex.settings.issuer;
    extraConfig = ''
      ${caddyHelpers.mkWaf { }}
      reverse_proxy ${config.services.dex.settings.web.http}
    '';
  };
}
