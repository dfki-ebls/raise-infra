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

  # https://github.com/fabriziosalmi/caddy-waf/releases
  caddy-waf-src = pkgs.fetchFromGitHub {
    owner = "fabriziosalmi";
    repo = "caddy-waf";
    tag = "v0.3.0";
    hash = "sha256-scav5J/38wbrdN+oD587qUFaC1EovXeajWvs+QNcK9s=";
  };

  defaultIncludeFiles = [
    "insecure-deserialization.json" # 5 rules — Java/PHP/Python/YAML deserialization
    "lfi.json" # 19 rules — path traversal, sensitive file access
    "rce.json" # 18 rules — command injection, shell execution
    "rfi.json" # 17 rules — remote file inclusion
    "smuggling.json" # 6 rules — HTTP request smuggling
    "sql-injection.json" # 23 rules — SQLi patterns
    "ssrf.json" # 8 rules — server-side request forgery
    "ssti.json" # 14 rules — template injection
    "vulnerability.json" # 17 rules — mixed XSS/SQLi/RCE/LFI/Log4j signatures
    "xss.json" # 21 rules — cross-site scripting
    "xxe.json" # 6 rules — XML external entity injection
  ];
  # Not included: spiderlabs.json (600+ OWASP CRS, log-only score 1),
  # authentication.json, csfr.json, data-validation.json, graphql.json, hpp.json

  defaultExcludeRules = [
    "idor-attacks" # logs numeric IDs, extremely noisy for REST APIs
    "open-redirect-attempt" # breaks OAuth redirect URIs
    "rce-commands-expanded" # blocks common words (curl, echo, python) in ARGS/HEADERS
    "rfi-http-url" # blocks any HTTP URL in params, breaks OAuth flows
    "unusual-paths" # blocks /admin, /login — too broad
  ];

  mkRulesFile =
    {
      includeFiles ? defaultIncludeFiles,
      excludeRules ? defaultExcludeRules,
    }:
    let
      filePaths = map (f: "${caddy-waf-src}/rules/${f}") includeFiles;
      excludeRuleIds = builtins.toJSON excludeRules;
    in
    pkgs.runCommand "waf-rules.json" { nativeBuildInputs = [ pkgs.jq ]; } ''
      ${lib.getExe pkgs.jq} -s \
        --argjson exclude '${excludeRuleIds}' \
        '[.[][] | select(.id as $id | $exclude | index($id) | not)]' \
        ${lib.concatStringsSep " " filePaths} > $out
    '';

  mkWaf =
    {
      countries ? [ "DE" ],
      includeFiles ? defaultIncludeFiles,
      excludeRules ? defaultExcludeRules,
      rateLimit ? {
        requests = 100;
        window = "1m";
        cleanupInterval = "5m";
      },
      anomalyThreshold ? 10,
      maxRequestBodySize ? "10MB",
      logSeverity ? "info",
      extraConfig ? "",
    }:
    lib.optionalString config.custom.enableWaf ''
      waf {
        rule_file ${mkRulesFile { inherit includeFiles excludeRules; }}
        anomaly_threshold ${toString anomalyThreshold}
        whitelist_countries ${countryDb} ${toString countries}
        geoip_fail_open
        max_request_body_size ${maxRequestBodySize}
        log_severity ${logSeverity}
        log_json
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
      defaultIncludeFiles
      defaultExcludeRules
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
