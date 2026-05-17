{
  pkgs,
  config,
  lib,
  ...
}:
let
  mkHost = domain: "${if config.custom.enableCertificates then "https" else "http"}://${domain}";
  mkSubHost = prefix: mkHost "${prefix}.${config.custom.rootDomain}";

  # Baseline response headers applied to every public vhost. HSTS is only
  # meaningful over HTTPS — browsers ignore the header on plaintext
  # responses per RFC 6797 §7.2, so we drop it when certificates are off
  # to avoid noise. `frame-ancestors 'none'` is a content-agnostic
  # framing block; if a downstream app needs framing, override with a
  # vhost-specific `header` block after this snippet. `X-Frame-Options`
  # is redundant with `frame-ancestors` on modern browsers but cheap
  # defense-in-depth for legacy UAs that ignore CSP framing directives.
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

  # Caddyfile snippet that 403s any request whose source IP isn't in `sources` (CIDRs); empty list = no restriction.
  # Wrapped in a `handle` because the Caddyfile adapter sorts top-level
  # `respond` after `handle`, so a bare `respond @blocked` is shadowed by
  # any catch-all `handle { … }` in the same site. `handle` blocks are
  # mutually exclusive and evaluated in source order — combined with
  # `lib.mkBefore` at the call site this guarantees the deny path runs
  # first.
  # `client_ip` (not `remote_ip`) so that adding a CDN/edge proxy in
  # front later is a config-only change: set `servers { trusted_proxies
  # static <cidrs> }` in `globalConfig` and Caddy will start honouring
  # `X-Forwarded-For` from those peers. Without `trusted_proxies` set,
  # `client_ip` falls back to the immediate peer, so XFF can't be spoofed.
  mkAllowedSources =
    sources:
    lib.optionalString (sources != [ ]) ''
      @blocked not client_ip ${toString sources}
      handle @blocked {
        respond "Access denied: Your IP is not allowed to access this resource." 403
      }
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

  # Custom rules appended on top of the curated upstream set. The plugin
  # parses the JSON via the `Rule` struct (`types.go:71`) — note the
  # mode field is keyed as `mode` despite the Go field being `Action`,
  # and the upstream `rules.json` ships with the wrong key (`action`),
  # which is why none of upstream's `"action": "block"` rules actually
  # short-circuit — they only contribute to the anomaly score. Keep
  # `mode` here so explicit blocks work.
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

  # Default JSON block responses; nicer than the plugin's plain-text
  # "Request blocked by WAF" body, especially for an API consumed by
  # the SPA via fetch().
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
      # Optional blocklists. The plugin hot-reloads these via fsnotify
      # when the file is rewritten, so an operator can drop in CIDRs or
      # domains without restarting Caddy. Paths must exist at startup
      # (caddy-waf does not tolerate missing files), so default to
      # plugin-shipped empty stubs in /nix/store; override with a
      # mutable path on disk to make hot-reload useful.
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

  # Curated honeypot paths we never serve. WAF's `sensitive-files`
  # rule covers /.git/, /.env, etc; this snippet kills the rest
  # (WordPress probes, PHPMyAdmin, AWS/SSH credential paths) before
  # the WAF burns cycles inspecting them.
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
    globalConfig = ''
      admin off
      persist_config off
      email ${config.custom.admin.mail}

      # Slow-loris defense. `read_header` and `read_body` are safe to
      # tighten site-wide — `read_body` caps any single body read, not
      # the whole upload, so a 60 MB upload over a slow link is fine.
      # `read` (whole-request) would break those uploads and is left
      # unset. `write` is also unset: it'd terminate long SSE streams
      # (LLM generations, conversion progress) since Caddy applies it
      # to the response writer even with `flush_interval -1`. `idle`
      # is the per-connection keep-alive cap.
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
    enableReload = false; # requires admin api
  };

  systemd.services.caddy = lib.mkIf config.custom.enableWaf {
    wants = [ "geoip-update.service" ];
    after = [ "geoip-update.service" ];
  };
}
