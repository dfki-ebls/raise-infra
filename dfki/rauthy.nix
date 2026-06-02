{
  config,
  lib,
  ...
}:
let
  mail = "raise@wi2.uni-trier.de";

  # Operator-managed env file for user secrets such as `SMTP_PASSWORD`, kept out
  # of the Nix store. Loaded after the auto-generated `/etc/rauthy/bootstrap.env`
  # so it can override it. Created empty (0600, root) on activation so the unit's
  # `EnvironmentFile` does not fail before the secret is provisioned via:
  #   printf 'SMTP_PASSWORD=%s\n' '<secret>' > /etc/rauthy/rauthy.env
  #   systemctl restart rauthy
  secretsEnvFile = "/etc/rauthy/rauthy.env";
in
{
  config = lib.mkIf config.custom.rauthy.enable {
    systemd.tmpfiles.rules = [ "f ${secretsEnvFile} 0600 root root -" ];

    custom.rauthy = {
      environmentFile = secretsEnvFile;

      # SMTP via the uni Trier relay. Port 465 (implicit TLS/SSL) maps to
      # Rauthy's default connection mode, which builds a lettre `relay()`
      # transport over TLS. https://sebadob.github.io/rauthy/config/config.html
      settings.email = {
        smtp_url = "mail.wi2.uni-trier.de";
        smtp_port = 465;
        smtp_username = mail;
        smtp_from = "RAISE IAM <${mail}>";
        sub_prefix = "RAISE IAM";
      };
    };
  };
}
