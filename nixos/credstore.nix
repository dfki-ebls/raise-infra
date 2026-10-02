{ config, lib, ... }:
let
  credstore = "/etc/credstore";
  encrypted = "/etc/credstore.encrypted";

  # systemd accepts `*` only as the last character of an imported name.
  matches =
    name: pattern:
    if lib.hasSuffix "*" pattern then
      lib.hasPrefix (lib.removeSuffix "*" pattern) name
    else
      pattern == name;

  consumers = lib.mapAttrs (
    name: _:
    lib.mapAttrsToList (unit: _: "${unit}.service") (
      lib.filterAttrs (
        _: service: lib.any (matches name) (lib.toList (service.serviceConfig.ImportCredential or [ ]))
      ) config.systemd.services
    )
  ) config.custom.credstore;
in
{
  options.custom.credstore = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    example."vllm.watermark-key" = "od -An -N8 -tu8 /dev/urandom | tr -d ' '";
    description = ''
      Credentials generated into `${credstore}` if missing, keyed by name,
      with the shell command printing the secret as value. Each is generated
      before every service importing it and never overwritten, also not while
      it exists in `${encrypted}`.
    '';
  };

  config = {
    assertions = lib.mapAttrsToList (name: units: {
      assertion = units != [ ];
      message = "custom.credstore.${name} is imported by no service, so it would never be generated.";
    }) consumers;

    systemd.services = lib.mapAttrs' (
      name: generate:
      lib.nameValuePair "credstore-${name}" {
        description = "Generate credential ${name} if missing";
        requiredBy = consumers.${name};
        before = consumers.${name};
        unitConfig.ConditionPathExists = [
          "!${credstore}/${name}"
          "!${encrypted}/${name}"
        ];
        serviceConfig = {
          Type = "oneshot";
          UMask = "0077";
        };
        script = ''
          set -o pipefail
          secret=$(${generate})
          printf '%s' "$secret" > ${credstore}/${name}
        '';
      }
    ) config.custom.credstore;
  };
}
