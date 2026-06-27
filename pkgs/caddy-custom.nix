{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-7ythRvWRsIIwOUNQm5TjAsgqtIYmekMke6gKicQMHLA=";
}
