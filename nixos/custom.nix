{ lib, ... }:

{
  options.custom = {
    rootDomain = lib.mkOption {
      type = lib.types.str;
      default = "raise.dfki.dev";
      description = "The root domain for all services.";
    };
    enableCertificates = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to use secure connections (HTTPS) for services.";
    };
  };
}
