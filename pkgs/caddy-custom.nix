{ caddy }:
caddy.withPlugins {
  plugins = [
    # https://github.com/fabriziosalmi/caddy-waf/releases
    "github.com/fabriziosalmi/caddy-waf@v0.3.0"
  ];
  hash = "sha256-c+dTA8sGkeMiAUmpdMt9zEQ3WjlC4cpPCcnI1Iz9W7E=";
}
