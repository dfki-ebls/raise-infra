{ lib', inputs, ... }:
{
  imports = [
    inputs.quadlet-nix.nixosModules.default
    inputs.determinate.nixosModules.default
  ]
  ++ lib'.flocken.getModules ./.;

  i18n.defaultLocale = "en_US.UTF-8";
  time.timeZone = "Europe/Berlin";
  system.stateVersion = "25.11";
  documentation.man.cache.enable = false;
  hardware.enableAllFirmware = true;

  security = {
    sudo-rs = {
      enable = true;
      execWheelOnly = true;
    };
  };

  environment.variables.BROWSER = "echo";

  boot.loader = {
    systemd-boot.configurationLimit = 10;
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };
  boot.initrd.systemd.enable = true;

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
