{ ... }:
{
  services.authelia.instances.main = {
    enable = false;
    secrets = {
      jwtSecretFile = "/etc/authelia/jwt-secret.txt";
      oidcHmacSecretFile = "/etc/authelia/oidc-hmac-secret.txt";
      oidcIssuerPrivateKeyFile = "/etc/authelia/oidc-issuer-private-key.txt";
      sessionSecretFile = "/etc/authelia/session-secret.txt";
      storageEncryptionKeyFile = "/etc/authelia/storage-encryption-key.txt";
    };
    environmentVariables = {
      X_AUTHELIA_CONFIG_FILTERS = "template";
    };
    settings = {
      theme = "dark";
      default_2fa_method = "totp";
      server.address = "tcp://0.0.0.0:9091";
      log = {
        level = "debug";
      };
      authentication_backend = {
        file.path = "/var/lib/authelia/users_database.yml";
      };
      access_control = {
        rules = [
          {
            domain = "public.example.com";
            policy = "bypass";
          }
          {
            domain = "domain.example.com";
            policy = "one_factor";
          }
        ];
      };
      session = {
        name = "authelia_session";
        cookies = [
          {
            domain = "example.com";
            authelia_url = "https://auth.example.com";
          }
        ];
      };
      storage = {
        local.path = "/var/lib/authelia/db.sqlite3";
      };
      notifier = {
        filesystem.filename = "/var/lib/authelia/notification.txt";
      };
      identity_providers.oidc = {
        clients = [
          {
            client_id = "todo";
            client_name = "TODO";
            client_secret = ''{{ fileContent "/etc/authelia/oidc-client-secret-todo.txt" }}'';
          }
        ];
      };
    };
  };
}
