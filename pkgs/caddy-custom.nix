{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-uUYds3PGZ4b/MR81ZzzodRhnr38WAwQqmRvOzeo0bXU=";
}
