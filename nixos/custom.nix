{ lib, ... }:

{
  options.custom = {
    rootDomain = lib.mkOption {
      type = lib.types.str;
      default = "raise.dfki.de";
      description = "The root domain for all services.";
    };
    vhostSuffix = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Suffix to append to all Caddy virtual host names (e.g., ':80' for local development).";
    };
  };
}
