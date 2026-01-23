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
