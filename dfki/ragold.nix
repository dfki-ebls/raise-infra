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
      root * ${ragold}
      encode zstd gzip

      @immutable path /assets/*
      header @immutable Cache-Control "public, max-age=31536000, immutable"

      @html not path /assets/*
      header @html Cache-Control "no-store"

      header {
        -ETag
        -Last-Modified
      }

      try_files {path} /index.html
      file_server
    '';
  };
}
