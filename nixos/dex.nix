{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.dex = {
    enable = false;
    # environmentFile = "/etc/dex/dex.env";
    settings = {
      issuer = "https://auth.${config.custom.rootDomain}";
      web = {
        http = "127.0.0.1:5556";
        allowedOrigins = [
          "https://app.${config.custom.rootDomain}"
        ];
      };
      storage = {
        type = "sqlite3";
        config.file = "/var/lib/dex/dex.db";
      };
      enablePasswordDB = true;
      # https://dexidp.io/docs/configuration/custom-scopes-claims-clients/
      staticClients = [
        {
          id = "default";
          name = "Default Client";
          public = true;
          redirectURIs = [
            "https://app.${config.custom.rootDomain}/auth/callback"
          ];
        }
      ];
    };
  };
  systemd.services.dex = {
    serviceConfig = {
      # Creates $STATE_DIRECTORY below /var/lib/private because DynamicUser=true,
      # but it gets symlinked into /var/lib/dex inside the unit
      StateDirectory = "dex";

      # Make /etc/dex/users.yaml available to the service at runtime as a credential
      # Minus: do not fail the unit if the file is missing
      LoadCredential = [ "-users.yaml:/etc/dex/users.yaml" ];

      # Append our merge after the upstream module’s ExecStartPre steps
      # https://github.com/NixOS/nixpkgs/blob/88d3861acdd3d2f0e361767018218e51810df8a1/nixos/modules/services/web-apps/dex.nix#L109
      ExecStartPre = lib.mkAfter [
        "+${pkgs.writeShellScript "dex-merge-users" ''
          set -euo pipefail

          USERS_YAML="$CREDENTIALS_DIRECTORY/users.yaml"

          # If missing, do nothing and continue
          if [ ! -s "$USERS_YAML" ]; then
            exit 0
          fi

          ${lib.getExe pkgs.yq-go} eval-all \
            'select(fileIndex==0) * select(fileIndex==1)' \
            /run/dex/config.yaml "$USERS_YAML" > /run/dex/config.yaml.tmp

          mv /run/dex/config.yaml.tmp /run/dex/config.yaml
          chmod 600 /run/dex/config.yaml
        ''}"
      ];
    };
  };

  # restart Dex when users.yaml changes
  systemd.paths.dex-users = {
    wantedBy = [ "multi-user.target" ];
    pathConfig = {
      PathExists = "/etc/dex/users.yaml";
      PathChanged = "/etc/dex/users.yaml";
    };
    unitConfig.Unit = "dex.service";
  };
}
