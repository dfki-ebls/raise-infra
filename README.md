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
