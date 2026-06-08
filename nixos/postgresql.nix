{ pkgs, config, ... }:
{
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_18;
    extensions = ps: [ ps.pgvector ];
  };

  services.postgresqlBackup = {
    enable = true;
    compression = "zstd";
    databases = config.services.postgresql.ensureDatabases;
    pgdumpOptions = "--clean --if-exists --no-owner --no-acl";
  };
}
