{ caddy }:
caddy.withPlugins {
  plugins = [
    # https://github.com/fabriziosalmi/caddy-waf/releases
    "github.com/fabriziosalmi/caddy-waf@v0.3.3"
  ];
  hash = "sha256-wKG8kLd1cB4bQaY/0vWjdY3b/w8sJqpmdGsg23ZcEPY=";
}
