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
        uid = 502;
        group = "quadlet";
        linger = false;
        subUidRanges = [
          {
            startUid = 200000;
            count = 65536;
          }
        ];
        subGidRanges = [
          {
            startGid = 300000;
            count = 65536;
          }
        ];
      };
    };
    groups = {
      ${admin.login}.gid = config.users.users.${admin.login}.uid;
      quadlet.gid = config.users.users.quadlet.uid;
    };
  };
}
