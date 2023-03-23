{ pkgs, config, ... }:

{
  networking.firewall = {
    # enable the firewall
    enable = true;

    # allow you to SSH in over the public internet
    allowedTCPPorts = [ 22 ];
  };
}
