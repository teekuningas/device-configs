{ config, pkgs, lib, inputs, ... }:

{
  nixpkgs.overlays = [
    (self: super: {
      # pipewire = super.pipewire.overrideAttrs (oldAttrs: rec {
      #   version = "1.3.83";
      #   src = super.fetchFromGitLab {
      #     domain = "gitlab.freedesktop.org";
      #     owner = "pipewire";
      #     repo = "pipewire";
      #     rev = version;
      #     sha256 = "sha256-atOvk7AMWZ7A9DnQQunVXlzGAVK3ITU85DkUfUsAJr4=";
      #   };
      #   buildInputs = oldAttrs.buildInputs ++ [ super.libebur128 ];
      # });
      # libcamera = super.libcamera.overrideAttrs (oldAttrs: rec {
      #   version = "0.4.0.bugfix";
      #   src = super.fetchgit {
      #     url = "https://git.libcamera.org/libcamera/libcamera.git";
      #     rev = "d748bdc66d3344761292adc8a611b74e4dfeb88f";
      #     hash = "sha256-5j8VY0eFTpNw2ujKkWzON1ZaqAAYFuptE2dnHevZsXo=";
      #   };
      # });
      # libadwaita = super.libadwaita.overrideAttrs (oldAttrs: rec {
      #   doCheck = false;
      # });
    })
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "procyon-nixos";

  # Enable networking
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "systemd-resolved";

  # Enable systemd-resolved
  services.resolved.enable = true;

  # Enable tailscale
  services.tailscale.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Helsinki";

  # Select internationalisation properties.
  i18n.defaultLocale = "fi_FI.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fi_FI.UTF-8";
    LC_IDENTIFICATION = "fi_FI.UTF-8";
    LC_MEASUREMENT = "fi_FI.UTF-8";
    LC_MONETARY = "fi_FI.UTF-8";
    LC_NAME = "fi_FI.UTF-8";
    LC_NUMERIC = "fi_FI.UTF-8";
    LC_PAPER = "fi_FI.UTF-8";
    LC_TELEPHONE = "fi_FI.UTF-8";
    LC_TIME = "fi_FI.UTF-8";
  };

  # Enable the X11 windowing system.
  services.xserver.enable = true;

  # Enable the GNOME Desktop Environment.
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  services.thermald.enable = true;
  # powerManagement.powertop.enable = true;

  hardware.graphics.enable = true;

  # note nixos-hardware import which sets up some of the options
  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.beta;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    nvidiaSettings = true;
    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;
      };
    };
  };

  # container toolkit
  hardware.nvidia-container-toolkit.enable = true;

  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Enable swap space
  swapDevices = [{
    device = "/var/lib/swapfile";
    size = 16 * 1024;
  }];

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "fi";
    variant = "";
  };

  # Configure console keymap
  console.keyMap = "fi";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.erpipehe = {
    isNormalUser = true;
    description = "Erkka";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = with pkgs; [ ];
  };

  fonts.packages = builtins.filter lib.attrsets.isDerivation (builtins.attrValues pkgs.nerd-fonts);

  tee-options.python-packages = [ "llm" "llm-ollama" "jupyterlab" "ipywidgets" "matplotlib" "scipy" "pandas" "geopandas" "folium" ];

  environment.systemPackages = with pkgs; [
    inputs.teepkgs.packages."${pkgs.system}".files-to-prompt
    (pkgs.buildFHSEnv {
      name = "uv";
      targetPkgs = pkgs: with pkgs; [ uv zlib ];
      runScript = "uv";
      profile = ''
        export LD_LIBRARY_PATH="${config.hardware.nvidia.package}/lib"
      '';
    })
    nodejs
    obsidian
    podman
    podman-compose
    powertop
    spotify
    teams-for-linux
  ];

  nix.settings.trusted-users = [ "erpipehe" ];

  virtualisation.podman = {
    enable = true;
    dockerCompat = lib.mkDefault true;
  };
  # To mitigate problem with "trigger-limit-hit" for podman.service
  systemd.user.sockets.podman.socketConfig = {
    TriggerLimitIntervalSec = "10s";
    TriggerLimitBurst = 1000;
  };
  # To remove problem of missing newuidmap binary for podman.service
  systemd.user.services.podman.path = [ "/run/wrappers/" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?

}
