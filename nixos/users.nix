{ config, pkgs, ... }:
let
  admin = config.custom.admin;
in
{
  users = {
    mutableUsers = false;
    defaultUserShell = pkgs.fish;
    users = {
      ${admin.login} = {
        description = admin.name;
        uid = 1000;
        isNormalUser = true;
        group = admin.login;
        extraGroups = [ "wheel" ];
      };
    };
    groups = {
      ${admin.login}.gid = config.users.users.${admin.login}.uid;
    };
  };
}
