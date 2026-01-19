# RAISE Infrastructure

```bash
# proxmox image to deploy
nix build .#.packages.x86_64-linux.proxmox
# local qemu testing vm
nix build .#vm
```
