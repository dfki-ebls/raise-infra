{ ... }:
{
  programs = {
    bash.enable = true;
    fish.enable = true;
    zsh.enable = true;
    git.enable = true;
    nix-ld.enable = true;
    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };
  };
}
