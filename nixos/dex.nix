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
      enablePasswordDB = true;
      # https://dexidp.io/docs/configuration/custom-scopes-claims-clients/
      staticClients = [
        {
          id = "default";
          name = "Default Client";
          public = true;
          redirectURIs = [
            "${protocol}://app.${config.custom.rootDomain}/auth/callback"
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

      # Make /etc/dex/config.yaml available to the service at runtime as a credential
      LoadCredential = [ "config.yaml:/etc/dex/config.yaml" ];

      # Append our merge after the upstream module’s ExecStartPre steps
      # https://github.com/NixOS/nixpkgs/blob/88d3861acdd3d2f0e361767018218e51810df8a1/nixos/modules/services/web-apps/dex.nix#L109
      ExecStartPre = lib.mkAfter [
        (pkgs.writeShellScript "dex-merge-config" ''
          set -euo pipefail

          if [ ! -s "$CREDENTIALS_DIRECTORY/config.yaml" ]; then
            echo "/etc/dex/config.yaml is empty, skipping merge"
            exit 0
          fi

          ${lib.getExe pkgs.yq-go} eval-all \
            'select(fileIndex==0) * select(fileIndex==1)' \
            /run/dex/config.yaml "$CREDENTIALS_DIRECTORY/config.yaml" \
            | ${lib.getExe' pkgs.moreutils "sponge"} /run/dex/config.yaml
        '')
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
    "/etc/dex/config.yaml".f = {
      mode = "0600";
      user = "root";
      group = "root";
    };
  };

  # restart Dex when config.yaml changes
  systemd.paths.etc-dex-config = {
    wantedBy = [ "multi-user.target" ];
    pathConfig.PathChanged = "/etc/dex/config.yaml";
    unitConfig.Unit = "dex.service";
  };
}
