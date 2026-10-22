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
        ];
      };
      isg-tr = {
        description = "ISG Trier";
        uid = 1001;
        isNormalUser = true;
        group = "isg-tr";
        openssh.authorizedKeys.keys = [
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDTpxAZfLTEP+M65muqy/SMIf//BHk6QPG3pYHcFEz5cFU3VaNLviqitbpFqKbBr8KC0vcdk4mM3ca3ED+ng+FySqN1Vz011UVkvoLiTAdKxUR+WXVtEycU+kyc+nYtl/VJNaYa0qK6a5BAt/V+uIWlAy+0VIWRl7kPdhzuQbPLHE5Ej22I1gU180G92Uw+ktZHmReUXz0+bXUwSYQfYNBItAb/SjW5rhVFidSRg4j3pXU+Yuml7DyU8/ILjqpESGYOQct0ua/MOkgh05sZiMM8zJZFsEAZHkvS9OjWsZaRpTLoLe5cUyMhwUcrBFb5vfcdqnowqpWFtoJFFYVG8ARB2HBOmQ6K6kOJsV0txYBeAnw+qdNFm/FR9pHgJtse4W9HdbgbZ3x8Y+kWEHm5bOsaCYV0g1h1l+gsBrM7MyNv+ZYqgKx3qFIeRM9IbZJjlwa071pmSQTJvkUHr1gZLcEQjaSDMweeeqKESjaYw7fs9/QCXr/BIdG/tzVHl+5gQZ8tOGHmPFJ5yKbDyDxNhnKt01niTau2UtK2KP6TbsQc2eCmgbxw50gJPeNuJAAzghpiGQoKoj36ASfti72yWcla8qQzBX4MgUStoqtpRsdVjJFTPeYV66i9ayeJNcX67QsR/I/g91lZpcuH/KH7POrAC/K95+GsfLZXIjw/SW2onQ=="
        ];
      };
    };
    groups = {
      mlenz.gid = config.users.users.mlenz.uid;
      isg-tr.gid = config.users.users.isg-tr.uid;
    };
  };

  virtualisation.vmVariant.users.users.mlenz.password = "";
}
