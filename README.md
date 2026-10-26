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

`dfki/vpn.nix` restricts the internal vhosts (`rauthy`, `hivegent`) to the `client_ip` allowlist in the server-local drop-ins `/etc/caddy/vpn.d/*.caddy`.
Caddy resolves the import when it adapts its config at startup, so the allowlist lives only on the server and changes with a `systemctl restart caddy`, no rebuild.
The vhosts fail closed, so they answer 403 to everyone but loopback on a fresh image or when the drop-ins are missing.

Allow the DFKI VPN ranges by creating `/etc/caddy/vpn.d/allow.caddy`, then restarting Caddy:

```caddy
client_ip 136.199.0.0/16
client_ip 203.0.113.5
```

Each `client_ip` line is merged into one allowlist, so add or remove entries one per line.
Ranges and bare IPs are accepted interchangeably, so `203.0.113.5` allows that single host alongside the range.

## Rauthy

Rauthy is the OIDC identity provider.
Encryption and cluster secrets are generated on first start into the credential `/etc/credstore/rauthy.secrets`.
Rauthy encrypts data with that key, so regenerating it makes existing data unreadable.

User-managed secrets live in `/etc/rauthy/rauthy.env`, whose entries override the secrets file.
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

Runtime secrets are systemd credentials named after their component, and the unit imports every `hivegent.*` credential from the system credential store.
Hivegent maps `hivegent.<NAME>` to the setting of the variable `HIVEGENT_<NAME>`, so any setting can be a credential, while llmhop names its credentials after their `${cred:…}` references.
Secrets listed in `custom.credstore` (`nixos/credstore.nix`) are generated if missing, before the first service importing them starts.
Store any other one as a plain file in `/etc/credstore`, which systemd keeps readable by root only, and restart:

```bash
(umask 077; systemd-ask-password -n "MCP client secret:" > /etc/credstore/hivegent.MCP__CLIENT_SECRET)
systemctl restart hivegent
```

List the credentials the unit receives, without printing their values:

```bash
systemd-run --pipe --wait --quiet --property=ImportCredential='hivegent.*' systemd-creds list
```

To keep a secret encrypted at rest with the host key, and the TPM if present, write it to `/etc/credstore.encrypted` instead:

```bash
systemd-ask-password -n "MCP client secret:" | systemd-creds encrypt --name=hivegent.MCP__CLIENT_SECRET - /etc/credstore.encrypted/hivegent.MCP__CLIENT_SECRET
```

Remove a secret by deleting its file and restarting.

### Watermarking

vLLM marks the output of the model with `gumbel` (`nixos/vllm.nix`), and MTP stays off since speculative decoding needs `dual_key_gumbel` with probabilistic drafting, which is not yet tested on this card.
Deduplication also covers the prompt, since Gumbel sampling is deterministic per context and an agent retrying a failed tool call would otherwise regenerate the identical tokens.
This is vLLM's option for multi-turn non-distortion, at the cost of leaving text copied from the prompt unmarked, and the default 8192-position search window keeps its scanning cost bounded.
The detector `vllm-detector-watermark` shares that config and is reached through llmhop at `/route/watermark/detect`, which Hivegent's `transparency` section points at.
llmhop listens only on the unix socket `/run/llmhop/default.sock` (`nixos/llmhop.nix`), which only members of the `llmhop` group can use, so no other local process can request unmarked output.
Hivegent's dynamic user joins that group through `SupplementaryGroups`.
Both secrets come from `custom.credstore`:

- `vllm.watermark-key`, an unsigned 64-bit integer shared by the model and the detector, so changing it makes previously marked text undetectable.
- `hivegent.TRANSPARENCY__SECRET_KEY`, from which Hivegent derives the key that signs detection reports and export provenance, so changing it rotates that key.

Back up both, and see Hivegent's `docs/article-50-2-operations.md` for rotation and testing.
To restore a backup, write it to the same path before the units first start, or replace the file and restart them.

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
