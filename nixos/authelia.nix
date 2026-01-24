{
  config,
  pkgs,
  lib,
  ...
}:
let
  secretsDir = "/etc/authelia";
  cfg = config.services.authelia.instances.main;
  protocol = if config.custom.enableCertificates then "https" else "http";

  # https://www.authelia.com/reference/guides/passwords/#user--password-file
  mkUsersDatabaseYaml = passwordHash: ''
    users:
      mlenz:
        displayname: Mirko Lenz
        password: ${passwordHash}
        email: mirko.lenz@dfki.de
        groups:
          - admin
  '';

  generateSecretsScript = pkgs.writeShellScript "authelia-generate-secrets" /* bash */ ''
    mkdir -p ${secretsDir}
    chmod 700 ${secretsDir}
    mkdir -p /var/lib/authelia
    chmod 700 /var/lib/authelia

    # https://www.authelia.com/reference/guides/generating-secure-values/#generating-a-random-alphanumeric-string
    generate_random_secret() {
      local file="$1"
      if [ ! -f "$file" ]; then
        ${lib.getExe cfg.package} crypto rand --length 64 --charset alphanumeric > "$file"
        chmod 600 "$file"
        echo "Generated $file"
      fi
    }

    # https://www.authelia.com/reference/guides/generating-secure-values/#generating-an-rsa-keypair
    generate_rsa_keypair() {
      local private_key="$1"
      local public_key="$2"
      if [ ! -f "$private_key" ]; then
        local tmpdir
        tmpdir=$(mktemp -d)
        ${lib.getExe cfg.package} crypto pair rsa generate \
          --bits 4096 \
          --directory "$tmpdir"
        mv "$tmpdir/private.pem" "$private_key"
        mv "$tmpdir/public.pem" "$public_key"
        rmdir "$tmpdir"
        chmod 600 "$private_key"
        chmod 644 "$public_key"
        echo "Generated $private_key"
        echo "Generated $public_key"
      fi
    }

    # https://www.authelia.com/integration/openid-connect/frequently-asked-questions/#how-do-i-generate-a-client-identifier-or-client-secret
    generate_oidc_client_secret() {
      local hash_file="$1"
      local plaintext_file="$2"
      if [ ! -f "$hash_file" ]; then
        local output
        output=$(${lib.getExe cfg.package} crypto hash generate pbkdf2 \
          --variant sha512 --random --random.length 72 --random.charset rfc3986)
        echo "$output" | grep 'Random Password:' | sed 's/Random Password: //' > "$plaintext_file"
        echo "$output" | grep 'Digest:' | sed 's/Digest: //' > "$hash_file"
        chmod 600 "$hash_file"
        chmod 600 "$plaintext_file"
        echo "Generated $hash_file"
        echo "Generated $plaintext_file (plaintext for client)"
      fi
    }

    generate_users_database() {
      local db_file="$1"
      local plaintext_file="$2"
      if [ ! -f "$db_file" ]; then
        local output
        output=$(${lib.getExe cfg.package} crypto hash generate argon2 \
          --random --random.length 32 --random.charset alphanumeric)
        local password
        password=$(echo "$output" | grep 'Random Password:' | sed 's/Random Password: //')
        local hash
        hash=$(echo "$output" | grep 'Digest:' | sed 's/Digest: //')
        echo "${mkUsersDatabaseYaml "$hash"}" > "$db_file"
        echo "$password" > "$plaintext_file"
        chmod 600 "$db_file"
        chmod 600 "$plaintext_file"
        echo "Generated $db_file"
        echo "Generated $plaintext_file (plaintext password for admin user)"
      fi
    }

    generate_random_secret "${secretsDir}/jwt-secret"
    generate_random_secret "${secretsDir}/oidc-hmac-secret"
    generate_random_secret "${secretsDir}/session-secret"
    generate_random_secret "${secretsDir}/storage-encryption-key"

    generate_rsa_keypair "${secretsDir}/oidc-issuer-private-key.pem" "${secretsDir}/oidc-issuer-public-key.pem"
    generate_oidc_client_secret "${secretsDir}/oidc-client-secret-default.hash" "${secretsDir}/oidc-client-secret-default.txt"
    generate_users_database "/var/lib/authelia/users_database.yml" "${secretsDir}/admin-password.txt"
  '';
in
{
  systemd.services.authelia-generate-secrets = {
    enable = cfg.enable;
    description = "Generate Authelia secrets if missing";
    wantedBy = [ "authelia-${cfg.name}.service" ];
    before = [ "authelia-${cfg.name}.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = generateSecretsScript;
      RemainAfterExit = true;
    };
  };

  services.authelia.instances.main = {
    enable = false;
    secrets = {
      jwtSecretFile = "/etc/authelia/jwt-secret";
      oidcHmacSecretFile = "/etc/authelia/oidc-hmac-secret";
      oidcIssuerPrivateKeyFile = "/etc/authelia/oidc-issuer-private-key.pem";
      sessionSecretFile = "/etc/authelia/session-secret";
      storageEncryptionKeyFile = "/etc/authelia/storage-encryption-key";
    };
    environmentVariables = {
      X_AUTHELIA_CONFIG_FILTERS = "template";
    };
    settings = {
      theme = "dark";
      default_2fa_method = "totp";
      server.address = "tcp://127.0.0.1:9091";
      log = {
        level = "debug";
      };
      authentication_backend = {
        file.path = "/var/lib/authelia/users_database.yml";
      };
      access_control = {
        default_policy = "deny";
        rules = [ ];
      };
      session = {
        name = "authelia_session";
        cookies = [
          {
            domain = "authelia.${config.custom.rootDomain}";
            authelia_url = "${protocol}://authelia.${config.custom.rootDomain}/";
          }
        ];
      };
      # https://www.authelia.com/configuration/security/regulation/
      regulation = {
        max_retries = 3;
        find_time = "2m";
        ban_time = "5m";
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
            client_id = "default";
            client_name = "Default Client";
            client_secret = ''{{ fileContent "/etc/authelia/oidc-client-secret-default.hash" }}'';
          }
        ];
      };
    };
  };
}
