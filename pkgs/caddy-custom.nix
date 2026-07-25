{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-1rf07EO7hF0vqh+MOSZDfh+iS3V13nQ4D8Jf2HKlO/k=";
}
