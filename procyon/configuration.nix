{ config, pkgs, inputs, unstable-pkgs, ... }:

let
  # Build electron 40 with the system's mesa/libs to avoid GPU driver mismatch
  mkElectron = pkgs.callPackage
    "${pkgs.path}/pkgs/development/tools/electron/binary/generic.nix" {};
  electron-40 = mkElectron "40.10.2" {
    x86_64-linux = "sha256-AkYgFABgCsCJxRo28VqARbXbcjukK4ZPcyqbTkhzHpc=";
  };

  vasara-pkg = inputs.vasara-pkgs.packages.x86_64-linux.camunda-modeler;
  camunda-modeler = pkgs.runCommand "camunda-modeler" {
    nativeBuildInputs = [ pkgs.makeWrapper ];
  } ''
    mkdir -p $out/bin
    makeWrapper ${electron-40}/bin/electron $out/bin/camunda-modeler \
      --prefix PATH : "${unstable-pkgs.temurin-jre-bin-11}/bin" \
      --add-flags "${vasara-pkg}/var/lib/camunda/app.asar"
  '';
in
{
  nixpkgs.overlays = [
    (final: prev: {
      llama-cpp-vulkan = unstable-pkgs.llama-cpp-vulkan;
    })
  ];

  # electron 40 is EOL but required by camunda-modeler (see electron-40 above).
  nixpkgs.config.permittedInsecurePackages = [
    "electron-40.10.2"
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
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

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
    extraGroups = [ "networkmanager" "wheel" "libvirtd" ];
  };

  environment.systemPackages = with pkgs; [
    pnpm
    obsidian
    powertop
    spotify
    teams-for-linux
    vagrant
    pavucontrol
    camunda-modeler
    libreoffice
  ];

  # networking.extraHosts = "130.234.6.208 moniviestin.jyu.fi";

  nix.settings.trusted-users = [ "erpipehe" ];

  # libvirt
  virtualisation.libvirtd.enable = true;

  system.stateVersion = "24.05";
}
