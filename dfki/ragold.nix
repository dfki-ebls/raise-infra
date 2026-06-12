{
  config,
  pkgs,
  inputs,
  caddyHelpers,
  ...
}:
let
  admin = config.custom.admin;

  ragold = inputs.ragold.packages.${pkgs.stdenv.system}.default.overrideAttrs {
    VITE_CONTACT_INFO = "${admin.name} <${admin.mail}>";
  };
in
{
  services.caddy.virtualHosts.ragold = {
    hostName = caddyHelpers.mkSubHost "ragold";
    extraConfig = ''
      ${caddyHelpers.securityHeaders { }}
      root * ${ragold}
      encode zstd gzip

      header {
        -ETag
        -Last-Modified
      }

      handle /assets/* {
        header Cache-Control "public, max-age=31536000, immutable"
        file_server
      }

      handle {
        header Cache-Control "no-store"
        try_files {path} /index.html
        file_server
      }
    '';
  };
}
