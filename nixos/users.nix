{ config, ... }:
let
  admin = config.custom.admin;
in
{
  users = {
    mutableUsers = false;
    users = {
      ${admin.login} = {
        description = admin.name;
        uid = 1000;
        isNormalUser = true;
        group = admin.login;
        extraGroups = [ "wheel" ];
      };
      quadlet = {
        description = "Quadlet User";
        isSystemUser = true;
        uid = 500;
        group = "quadlet";
        linger = false;
        subUidRanges = [
          {
            startUid = 50000;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = 50000;
            count = 65536;
          }
        ];
      };
    };
    groups = {
      ${admin.login}.gid = 1000;
      quadlet.gid = 500;
    };
  };
}
