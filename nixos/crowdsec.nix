{ config, ... }:
{
  services.crowdsec = {
    enable = false;
    autoUpdateService = true;
    # https://app.crowdsec.net/hub/collections
    hub.collections = [
      "crowdsecurity/linux"
      "crowdsecurity/caddy"
    ];
    localConfig.acquisitions = [
      {
        filenames = [ "${config.services.caddy.logDir}/*.log" ];
        labels.type = "caddy";
      }
      {
        source = "journalctl";
        journalctl_filter = [
          "_SYSTEMD_UNIT=sshd.service"
        ];
        labels.type = "syslog";
      }
    ];
    localConfig.parsers.s02Enrich = [
      {
        name = "local-whitelist";
        filter = "true";
        whitelist = {
          reason = "internal network";
          cidr = [ "10.0.0.0/8" ];
        };
      }
    ];
  };
  services.crowdsec-firewall-bouncer = {
    enable = config.services.crowdsec.enable;
  };
  # todo: https://github.com/NixOS/nixpkgs/pull/476651
  systemd.services.crowdsec-firewall-bouncer = {
    partOf = [ "nftables.service" ];
    after = [ "nftables.service" ];
  };
}
