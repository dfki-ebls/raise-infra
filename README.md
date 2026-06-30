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

## VPN allowlist

`dfki/vpn.nix` makes the internal vhosts (`rauthy`, `hivegent`) import server-local Caddyfile drop-ins from `/etc/caddy/vpn.d/*.caddy`.
Caddy resolves the import when it adapts its config at startup, so the rules live only on the server and change with a `systemctl restart caddy`, no rebuild.
An import glob that matches no files is a no-op, so the vhosts stay unrestricted in CI and on a fresh image until a drop-in exists.

Restrict the internal services to the DFKI VPN ranges by creating `/etc/caddy/vpn.d/allow.caddy`, then restarting Caddy:

```caddy
@blocked not {
  client_ip 136.199.0.0/16
  client_ip 203.0.113.5
}
handle @blocked {
  respond "Access denied: Your IP is not allowed to access this resource." 403
}
```

Each `client_ip` line is merged into one allowlist that `not` blocks everyone outside of, so add or remove entries one per line.
Ranges and bare IPs are accepted interchangeably, so `203.0.113.5` allows that single host alongside the range.

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
The client secret is long lived until rotated, deleted, or the client is disabled.
Each returned bearer token is short lived and the token response includes `expires_in`.
The default token lifetime for a newly created Rauthy client is 1800 seconds unless changed in the client settings.

Fetch a token and call the API:

```bash
token=$(curl -fsS https://sso.<domain>/auth/v1/oidc/token \
  -d grant_type=client_credentials \
  -d client_id=hivegent-integration \
  -d client_secret=<secret> | jq -r .access_token)

curl -fsS https://hivegent.<domain>/api/documents -H "Authorization: Bearer $token"
```

For Python services, cache the token and refresh it shortly before it expires:

```python
from dataclasses import dataclass
from time import monotonic

import httpx


@dataclass(slots=True)
class ClientCredentialsAuth:
    token_url: str
    client_id: str
    client_secret: str
    access_token: str | None = None
    expires_at: float = 0.0

    async def headers(self, client: httpx.AsyncClient) -> dict[str, str]:
        access_token = self.access_token
        if access_token is None or monotonic() >= self.expires_at - 60:
            response = await client.post(
                self.token_url,
                data={
                    "grant_type": "client_credentials",
                    "client_id": self.client_id,
                    "client_secret": self.client_secret,
                },
                timeout=10,
            )
            response.raise_for_status()
            token = response.json()
            access_token = str(token["access_token"])
            self.access_token = access_token
            self.expires_at = monotonic() + int(token["expires_in"])

        return {"Authorization": f"Bearer {access_token}"}


async def list_documents(client: httpx.AsyncClient, auth: ClientCredentialsAuth) -> object:
    response = await client.get(
        "https://hivegent.<domain>/api/documents",
        headers=await auth.headers(client),
    )
    response.raise_for_status()
    return response.json()
```

Any service that already depends on Authlib can use its HTTPX OAuth client instead:
When the client stays open, Authlib renews expired client credentials tokens from `token_endpoint` before protected requests.

```python
from authlib.integrations.httpx_client import AsyncOAuth2Client


async def list_documents() -> object:
    async with AsyncOAuth2Client(
        "hivegent-integration",
        "<secret>",
        token_endpoint="https://sso.<domain>/auth/v1/oidc/token",
        token_endpoint_auth_method="client_secret_post",
    ) as client:
        await client.fetch_token(grant_type="client_credentials")
        response = await client.get("https://hivegent.<domain>/api/documents")
        response.raise_for_status()
        return response.json()
```

Rotate the secret from the same admin UI screen; nothing in the Nix store needs to change.
