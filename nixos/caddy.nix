{
  pkgs,
  config,
  lib,
  ...
}:
let
  mkHost = domain: "${if config.custom.enableCertificates then "https" else "http"}://${domain}";
  mkSubHost = prefix: mkHost "${prefix}.${config.custom.rootDomain}";

  # Baseline response headers for public vhosts.
  securityHeaders = ''
    header {
      X-Content-Type-Options nosniff
      X-Frame-Options DENY
      Referrer-Policy strict-origin-when-cross-origin
      Content-Security-Policy "frame-ancestors 'none'"
      -Server
      ${lib.optionalString config.custom.enableCertificates ''
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
      ''}
    }
  '';

  # Empty source lists mean no restriction.
  mkAllowedSources =
    sources:
    lib.optionalString (sources != [ ]) ''
      @blocked not client_ip ${toString sources}
      handle @blocked {
        respond "Access denied: Your IP is not allowed to access this resource." 403
      }
    '';

  countryDb = "${config.custom.geoip.databaseDir}/GeoLite2-Country.mmdb";

  # Curated caddy-waf upstream rules.
  defaultIncludeRules = [
    "block-scanners" # nikto/sqlmap/nmap/burpsuite/etc. User-Agents
    "crlf-injection-headers" # %0d%0a in headers
    "header-attacks-consolidated" # SQLi/XSS/path-traversal payloads in headers
    "http-request-smuggling" # Transfer-Encoding/Content-Length games
    "insecure-deserialization-java" # rO0AB / aced0005 magic bytes
    "jwt-tampering" # forged JWTs in Authorization/Cookie
    "path-traversal" # ../, %2e%2e, etc/passwd, /proc/self/environ
    "sensitive-files" # /.git/, /.env, /.htaccess, server-status, *.bak
    "sensitive-files-expanded" # narrower companion to sensitive-files
  ];

  # caddy-waf uses `mode`, not upstream's broken `action` key.
  defaultExtraRules = [
    {
      id = "method-disallowed";
      phase = 1;
      pattern = "^(TRACE|CONNECT|PROPFIND|PROPPATCH|MKCOL|COPY|MOVE|LOCK|UNLOCK|DEBUG|TRACK)$";
      targets = [ "METHOD" ];
      severity = "HIGH";
      score = 10;
      mode = "block";
      priority = 100;
      description = "Block HTTP methods the application does not use";
    }
  ];

  mkRuleFile =
    {
      includeRules,
      extraRules,
    }:
    pkgs.runCommand "waf-rules.json" { } ''
      ${lib.getExe pkgs.jq} \
        --argjson include '${lib.toJSON includeRules}' \
        --argjson extra '${lib.toJSON extraRules}' \
        '[.[] | select(.id as $id | $include | index($id))] + $extra' \
        ${pkgs.caddy-waf}/rules.json > $out
    '';

  wafBlockedJson = pkgs.writeText "waf-blocked.json" (
    builtins.toJSON {
      error = "blocked";
      detail = "Request blocked by web application firewall.";
    }
  );
  wafRatelimitedJson = pkgs.writeText "waf-ratelimited.json" (
    builtins.toJSON {
      error = "rate_limited";
      detail = "Too many requests.";
    }
  );

  mkWaf =
    {
      countries ? [ "DE" ],
      includeRules ? defaultIncludeRules,
      extraRules ? defaultExtraRules,
      rateLimit ? {
        requests = 100;
        window = "1m";
        cleanupInterval = "5m";
      },
      anomalyThreshold ? 10,
      logSeverity ? "info",
      # Optional caddy-waf blocklist files.
      ipBlacklistFile ? null,
      dnsBlacklistFile ? null,
      extraConfig ? "",
    }:
    lib.optionalString config.custom.enableWaf ''
      waf {
        rule_file ${mkRuleFile { inherit includeRules extraRules; }}
        anomaly_threshold ${toString anomalyThreshold}
        whitelist_countries ${countryDb} ${toString countries}
        log_path ${config.services.caddy.logDir}/waf.json
        log_severity ${logSeverity}
        redact_sensitive_data
        rate_limit {
          requests ${toString rateLimit.requests}
          window ${rateLimit.window}
          cleanup_interval ${rateLimit.cleanupInterval}
        }
        custom_response 403 application/json ${wafBlockedJson}
        custom_response 429 application/json ${wafRatelimitedJson}
        ${lib.optionalString (ipBlacklistFile != null) "ip_blacklist_file ${ipBlacklistFile}"}
        ${lib.optionalString (dnsBlacklistFile != null) "dns_blacklist_file ${dnsBlacklistFile}"}
        ${extraConfig}
      }
    '';

  # Curated honeypot paths we never serve.
  scannerHoneypots = ''
    @scanner path /wp-admin* /wp-login* /wp-content* /xmlrpc.php /phpmyadmin* /pma* /.aws/* /.ssh/* /administrator /admin.php /shell.php
    handle @scanner {
      respond 404
    }
  '';
in
{
  _module.args.caddyHelpers = {
    inherit
      mkHost
      mkSubHost
      mkAllowedSources
      mkWaf
      defaultIncludeRules
      scannerHoneypots
      securityHeaders
      ;
  };

  custom.geoip.enable = config.custom.enableWaf;

  services.caddy = {
    enable = true;
    package = pkgs.caddy-custom;
    openFirewall = true;
    email = config.custom.admin.mail;
    enableReload = false; # requires admin api
    globalConfig = ''
      admin off
      persist_config off

      # Slow-loris limits.
      servers {
        timeouts {
          read_header 10s
          read_body   30s
          idle        2m
        }
      }
    ''
    + lib.optionalString config.custom.enableWaf ''
      order waf first
    '';
  };

  systemd.services.caddy = lib.mkIf config.custom.enableWaf {
    wants = [ "geoip-update.service" ];
    after = [ "geoip-update.service" ];
  };
}
