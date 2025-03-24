# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only
  boot.supportedFilesystems = [ "ntfs" ];

  networking.hostName = "miaupad-nixos"; # Define your hostname.

  networking.wireless.enable =
    true; # Enables wireless support via wpa_supplicant.
  networking.wireless.userControlled.enable = true;
  networking.wireless.networks.miaurouter.pskRaw =
    "0b965df6955e2bb67e616eb784b6d750774424a72fe24cd747885ca366f60dd0";
  networking.wireless.networks.Kahvipoytaverkko.pskRaw =
    "521da256d31acd0ef1e3c33294594c4c30cced0330580ba0a4e6db6ec2b4bfe4";

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp3s0.useDHCP = true;
  networking.interfaces.wlp4s0.useDHCP = true;

  # networking.nameservers = [ "8.8.8.8" "4.4.4.4" ];

  # Set your time zone.
  time.timeZone = "Europe/Helsinki";

  # Select internationalisation properties.
  i18n.defaultLocale = "fi_FI.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    useXkbConfig = true;
  };

  services.displayManager = {
    sddm.enable = true;
    defaultSession = "none+awesome";
  };

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    windowManager.awesome = {
      enable = true;
      luaModules = with pkgs.luaPackages; [ luarocks luadbi-mysql ];
    };
  };

  # Configure keymap in X11
  services.xserver.xkb.layout = "fi";
  services.xserver.xkb.options = "eurosign:e";

  services.libinput.enable = true;

  # # Enable opengl
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [ libGL ];

  # hardware.bluetooth.enable = true;
  # services.blueman.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.zairex = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };

  powerManagement.powertop.enable = true;

  environment.systemPackages = with pkgs; [ powertop ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;

  # Enable CUPS
  services.printing.enable = true;

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 8008 8009 8010 ];
  networking.firewall.allowedUDPPortRanges = [{
    from = 32768;
    to = 61000;
  }];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "21.11"; # Did you read the comment?

}
