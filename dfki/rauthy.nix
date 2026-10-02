{
  config,
  lib,
  ...
}:
let
  mail = "raise@wi2.uni-trier.de";
in
{
  config = lib.mkIf config.custom.rauthy.enable {
    custom.rauthy = {
      # `SMTP_PASSWORD`, see README.
      environmentFile = "/etc/rauthy/rauthy.env";

      # SMTP via the uni Trier relay. Port 465 (implicit TLS/SSL) maps to
      # Rauthy's default connection mode, which builds a lettre `relay()`
      # transport over TLS. https://sebadob.github.io/rauthy/config/config.html
      settings.email = {
        smtp_url = "mail.wi2.uni-trier.de";
        smtp_port = 465;
        smtp_username = mail;
        smtp_from = "RAISE Single Sign-On <${mail}>";
        sub_prefix = "RAISE Single Sign-On";
      };
    };
  };
}
