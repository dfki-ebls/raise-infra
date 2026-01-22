# RAISE Infrastructure

```bash
# image to deploy
nix build .#.packages.x86_64-linux.image
# local vm for testing
nix build .#vm
# rebuild on machine
sudo nixos-rebuild --flake github:dfki-ebls/raise-infra#x86_64
```
