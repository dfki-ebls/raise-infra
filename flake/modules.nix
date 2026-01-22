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
        virtualization.diskSize = 128 * 1024; # MB
        proxmox = {
          qemuConf = {
            name = "raise";
            bios = "ovmf";
            cores = 8;
            memory = 16 * 1024;
            agent = true;
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
