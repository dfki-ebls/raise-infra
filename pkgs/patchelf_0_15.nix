# patchelf 0.19 corrupts executables rewritten more than once (NixOS/nixpkgs#577387).
# Mirrors the pin nixpkgs applies to cudaPackages, drop once the default patchelf is fixed.
{ patchelf, fetchurl }:
patchelf.overrideAttrs (
  finalAttrs: _: {
    version = "0.15.2";
    src = fetchurl {
      url = "https://github.com/NixOS/patchelf/releases/download/${finalAttrs.version}/patchelf-${finalAttrs.version}.tar.bz2";
      hash = "sha256-F3RfVkFZyOIo/EEtplogSLhGxLa0Igt3y/IkFuAvLXw=";
    };
  }
)
