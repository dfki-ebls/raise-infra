{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-O5aKDU/Vh4XF5hZPU7LlCrq83EPOw4b7h66QUF9Z5k8=";
}
