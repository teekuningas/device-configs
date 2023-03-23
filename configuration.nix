{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./networking.nix # generated at runtime by nixos-infect
    ./users.nix
    ./host.nix
  ];

  environment.systemPackages = with pkgs; [ vim git ];

  boot.cleanTmpDir = true;
  zramSwap.enable = true;

  networking.hostName = "miaucloud-nixos";
  networking.domain = "";

  services.openssh.enable = true;
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "22.11";
}
