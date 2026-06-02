# RAISE Infrastructure

```bash
# image to deploy
nix build .#.packages.x86_64-linux.image
# local vm for testing
nix build .#vm
# rebuild on machine
sudo nixos-rebuild --flake github:dfki-ebls/raise-infra#x86_64 --refresh switch
# connect to vm, web services are exposed on localhost:8888
ssh -o StrictHostKeychecking=no -o UserKnownHostsFile=/dev/null -A -p 2222 127.0.0.1
```

## Rauthy

Rauthy is the OIDC identity provider.
Encryption and cluster secrets in `/etc/rauthy/bootstrap.env` are generated automatically on first start.

To regenerate them, delete the file and restart:

```bash
rm /etc/rauthy/bootstrap.env && systemctl restart rauthy-generate-secrets rauthy
```

User-managed secrets live in `/etc/rauthy/rauthy.env`, loaded after the generated file so it can override it.
Rauthy sends mail through the uni Trier relay (`mail.wi2.uni-trier.de:465`, implicit TLS), and the SMTP password is the only secret kept out of the Nix store.
Provision it on the server, then restart:

```bash
printf 'SMTP_PASSWORD=%s\n' '<secret>' > /etc/rauthy/rauthy.env
systemctl restart rauthy
```

## Hivegent

Hivegent keeps its state in a local Postgres database shared with Rauthy.
It re-applies its Alembic migrations on every startup, so dropping the database is enough to start over.

Stop the backend, drop and recreate an empty database owned by the `hivegent` role, then start it again:

```bash
systemctl stop hivegent
sudo -u postgres psql \
  -c 'DROP DATABASE hivegent WITH (FORCE);' \
  -c 'CREATE DATABASE hivegent OWNER hivegent;'
systemctl start hivegent
```

Do not restart the `postgresql` service, since Rauthy shares the same instance.
To also wipe local files for a full reset, clear the state and cache while stopped: `rm -rf /var/lib/hivegent/* /var/cache/hivegent/*`.

Runtime secrets live in `/etc/hivegent/hivegent.env`, created empty on activation so startup never blocks before they are provisioned.

### Service integrations (client credentials)

The browser SPA client (`hivegent-spa`) is provisioned automatically on first DB init.
To let an external service call the API non-interactively, create a confidential client by hand in the Rauthy admin UI so its secret stays out of the Nix store.
In **Clients → Add Client** set:

- **Client ID**: `hivegent-integration`, or any id starting with `hivegent-` so it matches Hivegent's `auth.audience` prefix (`nixos/hivegent.nix`).
- **Confidential**: yes, since the client credentials grant requires a secret; copy the generated secret, as it is shown only once.
- **Enabled flows**: `client_credentials` only, with no redirect URIs.
- **Token algorithm**: EdDSA for both the access and ID token.
- **Scopes**: `openid` is enough; a client-credentials token carries no user, so it has no `groups` claim and the integration operates only on its own knowledge namespace (`user:hivegent-integration`), never shared group knowledge.

`access.client_credentials_map_sub` is already enabled in the Rauthy config, so the token's `sub` is the client id, which becomes the integration's identity in Hivegent.

Fetch a token and call the API:

```bash
token=$(curl -fsS https://rauthy.<domain>/auth/v1/oidc/token \
  -d grant_type=client_credentials \
  -d client_id=hivegent-integration \
  -d client_secret=<secret> | jq -r .access_token)

curl -fsS https://hivegent.<domain>/api/documents -H "Authorization: Bearer $token"
```

Rotate the secret from the same admin UI screen; nothing in the Nix store needs to change.
