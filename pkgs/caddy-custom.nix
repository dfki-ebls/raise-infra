{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-jgkoKmoLGtrEhoNR+xJsYX/otUBQUddIULeuT4lM6Os=";
}
