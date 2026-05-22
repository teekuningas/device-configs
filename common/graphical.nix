{ config, pkgs, lib, ... }:

{
  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [ gedit openconnect postman ];

  fonts.packages = builtins.filter lib.attrsets.isDerivation
    (builtins.attrValues pkgs.nerd-fonts);

}
