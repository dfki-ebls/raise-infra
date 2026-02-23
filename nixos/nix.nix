{ inputs, ... }:
{
  nix = {
    channel.enable = false;
    extraOptions = ''
      !include nix.secrets.conf
    '';
    settings = {
      sandbox = true;
      allowed-users = [ "@wheel" ];
      trusted-users = [ "@wheel" ];
      experimental-features = [
        "flakes"
        "impure-derivations"
        "nix-command"
        "no-url-literals"
        "pipe-operators"
      ];
      commit-lock-file-summary = "chore(deps): update flake.lock";
      download-buffer-size = 1000000000; # 1 GB
      keep-derivations = true;
      keep-failed = false;
      keep-going = true;
      keep-outputs = false;
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
