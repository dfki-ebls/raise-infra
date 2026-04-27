{ caddy }:
caddy.withPlugins {
  plugins = [
    # https://github.com/fabriziosalmi/caddy-waf/releases
    "github.com/fabriziosalmi/caddy-waf@v0.3.2"
  ];
  hash = "sha256-67EyPwLFPA1bi2D6ke8tvf6yckjas02pd+O1GNoLLVw=";
}
