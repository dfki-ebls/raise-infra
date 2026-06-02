{ lib', lib, ... }:
{
  imports = lib'.flocken.getModules ./.;

  options.custom = {
    rootDomain = lib.mkOption {
      type = lib.types.str;
      description = "The root domain for all services.";
    };
    enableGeoblocking = lib.mkEnableOption "country geoblocking for Caddy" // {
      default = true;
    };
    enableNvidia = lib.mkEnableOption "NVIDIA drivers for GPU support" // {
      default = true;
    };
    enableCertificates = lib.mkEnableOption "secure connections for services" // {
      default = true;
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
