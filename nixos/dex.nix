{ config, ... }:
{
  # Create admin user in portunus, then add $DEX_SEARCH_USER_PASSWORD to /etc/dex.env
  # On first run, the admin password is printed to stdout, access with `journalctl -u portunus.service -b` and change in UI
  services.portunus = {
    enable = false;
    domain = "sso.${config.custom.rootDomain}";
    port = 5558;
    ldap.searchUserName = "admin";
    dex = {
      enable = true;
      port = 5556;
    };
  };
  services.dex = {
    environmentFile = "/etc/dex.env";
    settings = {
      web.allowedOrigins = [
        "https://app.${config.custom.rootDomain}"
      ];
      # https://dexidp.io/docs/configuration/custom-scopes-claims-clients/
      staticClients = [
        {
          id = "default";
          name = "Default Client";
          public = true;
          redirectURIs = [
            "https://app.${config.custom.rootDomain}/sso/callback"
          ];
        }
      ];
    };
  };
}
