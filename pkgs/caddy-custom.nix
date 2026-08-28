{ caddy }:
caddy.withPlugins {
  plugins = [
    "github.com/porech/caddy-maxmind-geolocation@v1.0.3"
  ];
  hash = "sha256-uJVSRaSTc6ecT20et8ejFfojtvPk5HP2ovYGkkzPeJE=";
}
