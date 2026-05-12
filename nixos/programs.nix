{ ... }:
{
  programs = {
    bash.enable = true;
    fish = {
      enable = true;
      interactiveShellInit = ''
        set -g fish_greeting
      '';
    };
    zsh.enable = true;
    git.enable = true;
    neovim = {
      enable = true;
      defaultEditor = true;
      viAlias = true;
      vimAlias = true;
    };
  };
}
