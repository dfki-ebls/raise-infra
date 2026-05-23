{ caddy }:
caddy.withPlugins {
  plugins = [
    # https://github.com/fabriziosalmi/caddy-waf/releases
    "github.com/fabriziosalmi/caddy-waf@v0.3.3"
  ];
  hash = "sha256-6pS7p9LAuwlfQzOA08DFKRqzw6livLSTaw2NDLaAJHs=";
}
