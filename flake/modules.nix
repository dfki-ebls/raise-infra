{ ... }:
{
  flake.nixosModules = {
    default = ../nixos;
    dfki = ../dfki;
    # https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/proxmox-image.nix
    proxmox =
      { config, modulesPath, ... }:
      {
        imports = [
          "${modulesPath}/virtualisation/proxmox-image.nix"
        ];
        proxmox = {
          qemuConf = {
            name = config.networking.hostName;
            bios = "ovmf";
            cores = 8;
            memory = 16 * 1024;
            agent = true;
            additionalSpace = "8G";
            bootSize = "512M";
          };
          # https://pve.proxmox.com/pve-docs-7/qm.conf.5.html
          qemuExtraConf = {
            cpu = "host";
            machine = "q35";
          };
          cloudInit.enable = false;
        };
      };
  };
}
