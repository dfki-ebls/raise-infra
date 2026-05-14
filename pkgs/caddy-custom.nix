{ caddy }:
caddy.withPlugins {
  plugins = [
    # https://github.com/fabriziosalmi/caddy-waf/releases
    "github.com/fabriziosalmi/caddy-waf@v0.3.3"
  ];
  hash = "sha256-doNAd6FDYJZ6lzj7LRHgrEdXW0AvGcsPZUFI7ZyPpl0=";
}
