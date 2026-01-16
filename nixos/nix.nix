{ inputs, ... }:
{
  nix = {
    channel.enable = false;
    settings = {
      sandbox = true;
      experimental-features = [
        "flakes"
        "impure-derivations"
        "nix-command"
        "no-url-literals"
        "pipe-operators"
      ];
      commit-lock-file-summary = "chore(deps): update flake.lock";
      download-buffer-size = 1000000000; # 1 GB
      keep-derivations = false;
      keep-failed = false;
      keep-going = true;
      keep-outputs = true;
      log-lines = 200;
      warn-dirty = false;
    };
  };
  nixpkgs = {
    config = inputs.self.nixpkgsConfig;
    overlays = [
      inputs.self.overlays.default
    ];
  };
}
