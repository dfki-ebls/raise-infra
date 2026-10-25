{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-rzs1vI7H9voASiJv689DFsUYNlZK7vfJomzJSWTNRL4=";
}
