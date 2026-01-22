{ pkgs, ... }:
{
  networking = {
    useNetworkd = true;
    useHostResolvConf = false;
    firewall.enable = true;
    nftables.enable = true;
    hostName = "raise";
  };

  services.firewalld.enable = true;

  virtualisation.quadlet.networks = {
    internal.networkConfig = {
      Driver = "bridge";
      Options.metric = 400;
      Internal = true;
      # Subnet = [ "10.15.1.0/24" ];
    };
    external.networkConfig = {
      Driver = "bridge";
      Options.metric = 200;
      Internal = false;
      # Subnet = [ "10.15.2.0/24" ];
    };
  };
}
