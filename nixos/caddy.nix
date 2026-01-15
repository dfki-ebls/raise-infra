{
  caddyHostName ? "raise.dfki.de",
  ...
}:

{
  services.caddy = {
    enable = true;
    virtualHosts.${caddyHostName} = {
      extraConfig = ''
        respond "Hello World!"
      '';
    };
  };

  networking.firewall = {
    allowedTCPPorts = [
      80
      443
    ];
    allowedUDPPorts = [
      443
    ];
  };
}
