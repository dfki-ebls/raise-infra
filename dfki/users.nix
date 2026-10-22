{ config, ... }:
{
  users = {
    users = {
      mlenz = {
        description = config.custom.admin.name;
        uid = 1000;
        isNormalUser = true;
        group = "mlenz";
        extraGroups = [ "wheel" ];
        # no password set, authentication only via rssh
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFT0P6ZLB5QOtEdpPHCF0frL3WJEQQGEpMf2r010gYH3 mlenz@macbook"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPg/jZmSr0LiCm5FKAcF54UJXK8GNgDO4op0MiASNadb mlenz@iphone"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHTD8HTidTJM3RLmU+WW7tBlDz6L2x8zoHJhqzA6m3+B mlenz@1password"
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIq4FI/+G9JoUDXlUoKEdMtVnhapUScSqGg34r+jLgax mlenz@shellfish"
        ];
      };
    };
    groups = {
      mlenz.gid = config.users.users.mlenz.uid;
    };
  };

  virtualisation.vmVariant.users.users.mlenz.password = "";
}
