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

## Dex OIDC

Dex is the OIDC identity provider for local user authentication.
Secrets in `/etc/dex/dex.env` are generated automatically on first start.
The plaintext admin password is saved to `/etc/dex/admin-password.txt`.

To regenerate secrets, delete the env file and restart:

```bash
rm /etc/dex/dex.env && systemctl restart dex-generate-secrets dex
```

To add extra users, edit `/etc/dex/config.yaml` on the server (Dex restarts automatically on changes):

```yaml
staticPasswords:
  - email: alice@example.com
    username: alice
    hash: "$2a$12$..."
    userID: alice
```

Generate a bcrypt hash for a user password:

```bash
mkpasswd --method bcrypt --rounds 12
```
