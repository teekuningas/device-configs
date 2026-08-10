# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, unstable-pkgs, ... }:

{
  imports = [
    # Include the results of the hardware scan.
    ./hardware-configuration.nix
  ];

  nixpkgs.overlays = [
    (final: prev: {
      gemini-cli = unstable-pkgs.gemini-cli;
    })
  ];

  # Use the GRUB 2 boot loader.
  boot.loader.grub.enable = true;
  boot.loader.grub.device = "/dev/sda"; # or "nodev" for efi only
  boot.supportedFilesystems = [ "ntfs" ];

  networking.hostName = "miaupad-nixos"; # Define your hostname.

  networking.networkmanager.enable = true;
  programs.nm-applet.enable = true;

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
  services.xserver.displayManager.sessionCommands = ''
    ${pkgs.xorg.xrdb}/bin/xrdb -merge <<< "XTerm*termName: xterm-256color"
  '';

  # Enable the X11 windowing system.
  services.xserver = {
    enable = true;
    videoDrivers = [ "intel" ];
    windowManager.awesome = {
      enable = true;
      luaModules = with pkgs.luaPackages; [ luarocks luadbi-mysql ];
    };
  };

  # Configure keymap in X11
  services.xserver.xkb.layout = "fi";
  services.xserver.xkb.options = "eurosign:e";

  services.libinput = {
    enable = true;
    touchpad = {
      clickMethod = "buttonareas";
      tapping = true;
      naturalScrolling = true;
      disableWhileTyping = true;
    };
  };

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Automatic display management
  services.autorandr.enable = true;

  boot.kernelParams = [ 
    "psmouse.synaptics_intertouch=1" 
    "i915.enable_psr=0"
    "i915.enable_dp_mst=0"
    "video=HDMI-A-1:d"
  ];
  boot.initrd.kernelModules = [ "i915" ];

  # # Enable opengl
  hardware.graphics.enable = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [ 
    libGL
    intel-media-driver
    vaapiIntel
  ];
  hardware.enableRedistributableFirmware = true;

  # hardware.bluetooth.enable = true;
  # services.blueman.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.zairex = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "video" "audio" ];
  };

  powerManagement.powertop.enable = true;
  services.upower.enable = true;

  environment.systemPackages = with pkgs; [
    powertop
    upower
    gemini-cli
    xfce.xfce4-terminal
    pulsemixer
    pavucontrol
    xlayoutdisplay
    autorandr
    arandr
    spotify
    (python312.withPackages (ps: with ps; [
      numpy
      requests
      flake8
      twine
    ]))
  ];

  # Enable the OpenSSH daemon.
  services.openssh.enable = true;
  programs.ssh.startAgent = true;

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
