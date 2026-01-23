{
  config,
  lib,
  pkgs,
  ...
}:
{
  services.dex = {
    enable = false;
    environmentFile = "/etc/dex/dex.env";
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
      LoadCredential = [ "users.yaml:/etc/dex/users.yaml" ];

      # Append our merge after the upstream module’s ExecStartPre steps
      # https://github.com/NixOS/nixpkgs/blob/88d3861acdd3d2f0e361767018218e51810df8a1/nixos/modules/services/web-apps/dex.nix#L109
      ExecStartPre = lib.mkAfter [
        "+${pkgs.writeShellScript "dex-merge-users" ''
          set -euo pipefail

          ${lib.getExe pkgs.yq-go} eval-all \
            'select(fileIndex==0) * select(fileIndex==1)' \
            /run/dex/config.yaml "$CREDENTIALS_DIRECTORY/users.yaml" \
            > /run/dex/config.yaml.tmp

          mv /run/dex/config.yaml.tmp /run/dex/config.yaml
          chmod 600 /run/dex/config.yaml
        ''}"
      ];
    };
  };

  # ensure /etc/dex configuration files exist
  systemd.tmpfiles.settings."10-dex" = {
    "/etc/dex".d = {
      mode = "0750";
      user = "root";
      group = "root";
    };
    "/etc/dex/dex.env".f = {
      mode = "0600";
      user = "root";
      group = "root";
    };
    "/etc/dex/users.yaml".f = {
      mode = "0600";
      user = "root";
      group = "root";
    };
  };

  # restart Dex when users.yaml changes
  systemd.paths.dex-users = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "/etc/dex/users.yaml";
    unitConfig.Unit = "dex.service";
  };
}
