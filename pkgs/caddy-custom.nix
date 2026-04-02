{ caddy }:
caddy.withPlugins {
  plugins = [
    # https://github.com/fabriziosalmi/caddy-waf/releases
    "github.com/fabriziosalmi/caddy-waf@v0.3.0"
  ];
  hash = "sha256-cBAfvD2hbvsv8STeoVkmETemYAdO/uMx/fT4bv5T7h4=";
}
