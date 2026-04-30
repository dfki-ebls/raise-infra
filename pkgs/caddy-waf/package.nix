{ fetchFromGitHub, applyPatches }:
applyPatches {
  src = fetchFromGitHub {
    owner = "fabriziosalmi";
    repo = "caddy-waf";
    tag = "v0.3.3";
    hash = "sha256-awj7nNv0sT8DZ3Y1fl4KzvdRGeUdcvbvkMFIPqDAtQw=";
  };
  patches = [ ./json-escapes.patch ];
}
