{ config, pkgs, lib, ... }:

{
  # enable flakes
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfree = true;

  programs.neovim = {
    enable = true;
    vimAlias = true;
  };

  environment.systemPackages = with pkgs; [
    curl
    gitFull
    gnumake
    htop
    jq
    starship
    tmux
    wget
    tree
  ];
}
