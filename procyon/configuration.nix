{ config, pkgs, options, lib, inputs, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      gemini-cli = inputs.nixpkgs.legacyPackages.${prev.system}.gemini-cli;
      codex = inputs.nixpkgs.legacyPackages.${prev.system}.codex;
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

  # boot.kernelPackages = pkgs.linuxPackages_latest;

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

  fonts.packages = builtins.filter lib.attrsets.isDerivation
    (builtins.attrValues pkgs.nerd-fonts);

  environment.systemPackages = with pkgs; [
    (python312.withPackages (ps: with ps; [
      llm
      llm-ollama
      datasette
      jupyterlab
      jupytext
      ipywidgets
      matplotlib
      numpy
      requests
      flake8
      scipy
      pandas
      geopandas
      folium
      twine
      (ps.callPackage "${inputs.teepkgs}/pkgs/llm-azure/default.nix" {python3Packages = ps;})
      (ps.callPackage "${inputs.teepkgs}/pkgs/llm-echo/default.nix" {python3Packages = ps;})
      (ps.callPackage "${inputs.teepkgs}/pkgs/ospeak/default.nix" {python3Packages = ps;})
      (ps.callPackage "${inputs.teepkgs}/pkgs/files-to-prompt/default.nix" {python3Packages = ps;})
    ]))
    uv
    nodejs
    obsidian
    podman
    podman-compose
    powertop
    spotify
    teams-for-linux
    aider-chat
    gemini-cli
    codex
    devenv
  ];

  # networking.extraHosts = "130.234.6.208 moniviestin.jyu.fi";

  # For uv
  programs.nix-ld = {
    enable = true;
    libraries = options.programs.nix-ld.libraries.default ++ (
      with pkgs; [
        dbus
        fontconfig
        freetype
        glib
        libGL
        libxkbcommon
        xorg.libxcb
        xorg.libX11
        xorg.xcbutilwm
        xorg.xcbutilimage
        xorg.xcbutilkeysyms
        xorg.xcbutilrenderutil
      ]
    );
  };

  nix.settings.trusted-users = [ "erpipehe" ];

  virtualisation = {
    containers.containersConf.settings.network.default_rootless_network_cmd = "slirp4netns";
    podman = {
      enable = true;
      dockerCompat = lib.mkDefault true;
    };
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
