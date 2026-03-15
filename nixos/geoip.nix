{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.custom.geoip;
in
{
  options.custom.geoip = {
    enable = lib.mkEnableOption "GeoIP database downloads";
    databaseDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/geoip";
      readOnly = true;
      description = "Directory where GeoIP databases are stored.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.timers.geoip-update = {
      description = "Daily GeoLite2 database update";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    systemd.services.geoip-update = {
      description = "Download and verify GeoLite2 databases";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "geoip-update" /* bash */ ''
          set -euo pipefail

          mkdir -p "${cfg.databaseDir}"

          release=$(${lib.getExe pkgs.curl} -sSf "https://api.github.com/repos/P3TERX/GeoLite.mmdb/releases/latest")

          tag=$(echo "$release" | ${lib.getExe pkgs.jq} -r '.tag_name')

          if [ -f "${cfg.databaseDir}/version" ] && [ "$(cat "${cfg.databaseDir}/version")" = "$tag" ]; then
            echo "GeoIP databases already at version $tag, skipping download."
            exit 0
          fi

          echo "Updating GeoIP databases to version $tag..."

          assets=$(echo "$release" | ${lib.getExe pkgs.jq} -r '.assets[] | select(.digest != null) | "\(.name)\t\(.digest)"')

          while IFS=$'\t' read -r name digest; do
            expected=''${digest#sha256:}
            url="https://github.com/P3TERX/GeoLite.mmdb/releases/download/$tag/$name"
            tmp="${cfg.databaseDir}/$name.tmp"

            ${lib.getExe pkgs.curl} -sSfL -o "$tmp" "$url"

            actual=$(sha256sum "$tmp" | cut -d' ' -f1)

            if [ "$actual" != "$expected" ]; then
              echo "ERROR: SHA256 mismatch for $name (expected $expected, got $actual)"
              rm -f "$tmp"
              exit 1
            fi

            mv "$tmp" "${cfg.databaseDir}/$name"
            echo "Downloaded and verified $name"
          done <<< "$assets"

          echo "$tag" > "${cfg.databaseDir}/version"
          echo "GeoIP databases updated to version $tag."
        '';
      };
    };
  };
}
