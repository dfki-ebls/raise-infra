{ ... }:
{
  networking = {
    useNetworkd = true;
    useHostResolvConf = false;
    firewall.enable = true;
    nftables.enable = true;
    hostName = "raise";
  };

  services.firewalld.enable = true;
}
