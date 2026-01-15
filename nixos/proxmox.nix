{ ... }:
{
  proxmox = {
    qemuConf = {
      bios = "ovmf";
    };
    cloudInit.enable = false;
  };
}
