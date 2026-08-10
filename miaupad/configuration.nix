{ pkgs, unstable-pkgs, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      antigravity-cli = unstable-pkgs.antigravity-cli;
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
  services.udisks2.enable = true;
  services.udiskie.enable = true;

  environment.systemPackages = with pkgs; [
    powertop
    upower
    antigravity-cli
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

  system.stateVersion = "21.11";

}
