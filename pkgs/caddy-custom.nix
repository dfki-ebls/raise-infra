{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-KUnOYqIWaQWTGU4kk4JXp8jFh54pema+kE/1TFmSHuY=";
}
