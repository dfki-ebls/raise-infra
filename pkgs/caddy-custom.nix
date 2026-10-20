{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-n8hx6zaxjLOx509ZIcr+SxOwNW9CskD/AEVUoCJeeCE=";
}
