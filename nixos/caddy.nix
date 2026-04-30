{
  pkgs,
  config,
  lib,
  ...
}:
let
  mkHost = domain: "${if config.custom.enableCertificates then "https" else "http"}://${domain}";
  mkSubHost = prefix: mkHost "${prefix}.${config.custom.rootDomain}";

  # Caddyfile snippet that 403s any request whose source IP isn't in `sources` (CIDRs); empty list = no restriction.
  mkAllowedSources =
    sources:
    lib.optionalString (sources != [ ]) ''
      @blocked not remote_ip ${toString sources}
      respond @blocked 403
    '';

  countryDb = "${config.custom.geoip.databaseDir}/GeoLite2-Country.mmdb";

  # Curated allowlist of high-confidence rules from caddy-waf's upstream rules.json.
  # The per-category community rule files (rules/*.json) are too noisy for this
  # deployment and several have outright bugs (e.g. REQUEST_COOKIES is not a
  # valid extraction target in v0.3.3). The author's own rules.json is denser
  # and tighter, but contains its own broken rules — most notably four
  # browser-integrity rules that target invented pseudo-headers and would 403
  # every request. We keep only the rules that are tight, useful, and add
  # genuine defense-in-depth on top of the country whitelist + rate limit.
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

  mkRuleFile =
    includeRules:
    pkgs.runCommand "waf-rules.json" { } ''
      ${lib.getExe pkgs.jq} \
        --argjson include '${lib.toJSON includeRules}' \
        '[.[] | select(.id as $id | $include | index($id))]' \
        ${pkgs.caddy-waf}/rules.json > $out
    '';

  mkWaf =
    {
      countries ? [ "DE" ],
      includeRules ? defaultIncludeRules,
      rateLimit ? {
        requests = 100;
        window = "1m";
        cleanupInterval = "5m";
      },
      anomalyThreshold ? 10,
      logSeverity ? "info",
      extraConfig ? "",
    }:
    lib.optionalString config.custom.enableWaf ''
      waf {
        rule_file ${mkRuleFile includeRules}
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
        ${extraConfig}
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
      ;
  };

  custom.geoip.enable = config.custom.enableWaf;

  services.caddy = {
    enable = true;
    package = pkgs.caddy-custom;
    globalConfig = ''
      admin off
      persist_config off
      email ${config.custom.admin.mail}
    ''
    + lib.optionalString config.custom.enableWaf ''
      order waf first
    '';
    enableReload = false; # requires admin api
  };

  systemd.services.caddy = lib.mkIf config.custom.enableWaf {
    wants = [ "geoip-update.service" ];
    after = [ "geoip-update.service" ];
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [
      443
    ];
  };
}
