{ lib, ... }:

{
  options.custom = {
    rootDomain = lib.mkOption {
      type = lib.types.str;
      description = "The root domain for all services.";
    };
    enableCertificates = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to use secure connections (HTTPS) for services.";
    };
    admin = {
      login = lib.mkOption {
        type = lib.types.str;
        description = "Login name for the admin user.";
      };
      name = lib.mkOption {
        type = lib.types.str;
        description = "Display name of the admin user.";
      };
      mail = lib.mkOption {
        type = lib.types.str;
        description = "Email address of the admin user.";
      };
    };
  };
}
