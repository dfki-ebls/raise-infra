{ ... }:
{
  networking = {
    useNetworkd = true;
    useHostResolvConf = false;
    firewall.enable = true;
    nftables.enable = true;
    nameservers = [
      "1.1.1.1"
      "1.0.0.1"
      "2606:4700:4700::1111"
      "2606:4700:4700::1001"
    ];
  };
}
