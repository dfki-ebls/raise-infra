{ config, lib, ... }:
let
  cfg = config.services.llmhop;

  collisions = lib.pipe (lib.attrNames cfg.portsRegistry) [
    (lib.groupBy (name: toString cfg.portsRegistry.${name}))
    (lib.filterAttrs (_: owners: lib.length owners > 1))
  ];
in
{
  options.services.llmhop.portsRegistry = lib.mkOption {
    type = lib.types.attrsOf lib.types.port;
    default = { };
    internal = true;
    description = ''
      Internal registry of host ports reserved by llmhop backends and their
      auxiliary components (gateways, metrics endpoints). Keyed by
      `<backend>/<component>` so the global uniqueness assertion can name the
      colliding owners. Written by `_llmhop-lib.nix:mkConfig`; do not set
      directly.
    '';
  };

  config.assertions = [
    {
      assertion = collisions == { };
      message =
        "services.llmhop: host port collisions across backends:\n"
        + lib.concatStringsSep "\n" (
          map (port: "port ${port} reserved by ${lib.concatStringsSep ", " collisions.${port}}") (
            lib.naturalSort (lib.attrNames collisions)
          )
        );
    }
  ];
}
