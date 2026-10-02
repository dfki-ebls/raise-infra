{
  config,
  lib,
  ...
}:
let
  cfg = config.custom.rauthy;

  credential = "rauthy.secrets";
  fromSecrets = "$SECRETS";
  rauthy = lib.getExe cfg.package;
in
{
  config = lib.mkIf cfg.enable {
    # Rauthy's own generators print the `[cluster]` and `[encryption]` tables.
    custom.credstore.${credential} = "${rauthy} generate-secrets && ${rauthy} generate-enc-key";

    custom.rauthy = {
      secretsCredential = credential;
      settings = {
        cluster = {
          secret_raft = fromSecrets;
          secret_api = fromSecrets;
        };
        encryption = {
          keys = [ fromSecrets ];
          key_active = fromSecrets;
        };
      };
    };
  };
}
