{ ... }:
{
  flake.nixosModules = {
    default = ../nixos;
    proxmox =
      { modulesPath, ... }:
      {
        imports = [
          "${modulesPath}/virtualisation/proxmox-image.nix"
        ];
        proxmox = {
          qemuConf = {
            name = "raise";
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
