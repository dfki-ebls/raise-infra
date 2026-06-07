{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-LmBBm4nXbgYf/WkT064AYJsXi2MDeUDZu6NDhzuD8jg=";
}
