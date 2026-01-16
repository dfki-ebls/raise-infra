{ pkgs, ... }:
{
  users = {
    mutableUsers = false;
    users.mlenz = {
      description = "Mirko Lenz";
      home = "/home/mlenz";
      shell = pkgs.fish;
      uid = 1000;
      group = "mlenz";
      extraGroups = [
        "wheel"
        "users"
      ];
      isNormalUser = true;
      # no password set, authentication only via rssh
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFT0P6ZLB5QOtEdpPHCF0frL3WJEQQGEpMf2r010gYH3 mlenz@mirkos-macbook"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHTD8HTidTJM3RLmU+WW7tBlDz6L2x8zoHJhqzA6m3+B mlenz@1password"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIq4FI/+G9JoUDXlUoKEdMtVnhapUScSqGg34r+jLgax mlenz@shellfish"
      ];
    };
    groups.mlenz = {
      gid = 1000;
    };
    users.quadlet = {
      description = "Quadlet User";
      isSystemUser = true;
      uid = 500;
      group = "quadlet";
      linger = true;
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
    groups.quadlet = {
      gid = 500;
    };
  };
}
