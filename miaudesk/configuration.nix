{ config, options, lib, pkgs, inputs, unstable-pkgs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "zairex";
  wsl.wslConf.network.hostname = "miaudesk-nixos";

  # To make the nvidia-container-toolkit work properly, useWindowsDriver is needed.
  wsl.useWindowsDriver = true;

  # Enable pulseaudio to get working audio.
  services.pulseaudio.enable = true;

  # Set up nix-ld to allow using non-native nvidia drivers.
  programs.nix-ld = {
    enable = true;
    # for uv
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
  environment.variables = {
    # for nvidia-smi / cuda to work
    NIX_LD_LIBRARY_PATH = lib.mkForce (lib.makeLibraryPath [
      "/run/current-system/sw/share/nix-ld"
      "/usr/lib/wsl"
    ]);
  };
  environment.sessionVariables.LD_LIBRARY_PATH = ["/run/opengl-driver/lib/"];

  nixpkgs.overlays = [
    (final: prev: {
      # up-to-date versions
      gemini-cli = unstable-pkgs.gemini-cli;
      codex = unstable-pkgs.codex;
      opencode = unstable-pkgs.opencode;
      llama-cpp = unstable-pkgs.llama-cpp;
      github-copilot-cli = unstable-pkgs.github-copilot-cli;

      # Wrap devcontainer with podman via symlinkJoin to avoid rebuilding from source.
      devcontainer = prev.symlinkJoin {
        name = "devcontainer-with-podman";
        paths = [ prev.devcontainer ];
        nativeBuildInputs = [ prev.makeWrapper ];
        postBuild = ''
          wrapProgram $out/bin/devcontainer \
            --prefix PATH : ${
              prev.lib.makeBinPath [
                prev.git
                prev.podman
                prev.podman-compose
              ]
            } \
            --set DEVCONTAINER_DOCKER_PATH "${prev.podman}/bin/podman"
        '';
      };
    })
  ];

  ## Note, to make nvidia work within containers, it was necessary to run nvidia-ctk.
  ## The command to generate the cdi was:
  ## $ sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
  ##
  ## IMPORTANT: After generating the CDI, you MUST run the patch script to fix paths for NixOS:
  ## $ ./miaudesk/scripts/patch-nvidia-cdi.sh
  # virtualisation.docker = {
  #   enable = true;
  #   daemon.settings.features.cdi = true;
  # };

  virtualisation = {
    containers.containersConf.settings.network.default_rootless_network_cmd = "slirp4netns";
    podman = {
      enable = true;
      dockerCompat = true;
      defaultNetwork.settings.dns_enabled = true;
    };
  };
  
  # To mitigate problem with "trigger-limit-hit" for podman.service
  systemd.user.sockets.podman.socketConfig = {
    TriggerLimitIntervalSec = "10s";
    TriggerLimitBurst = 1000;
  };
  # To remove problem of missing newuidmap binary for podman.service
  systemd.user.services.podman.path = [ "/run/wrappers/" ];

  #users.users.zairex = {
  #  extraGroups = [
  #    "podman"
  #  ];
  #};

  environment.systemPackages = with pkgs; [
    (python312.withPackages (ps: with ps; [
      numpy
      cryptography
      requests
      flake8
      twine
      datasette
      jupyterlab
      jupytext
      ipywidgets
      matplotlib
      scipy
      pandas
      geopandas
      folium
      llm
      llm-azure
      llm-gemini
    ]))
    # llm
    uv
    cudatoolkit
    nvidia-container-toolkit
    aider-chat
    gemini-cli
    codex
    opencode
    llama-cpp
    github-copilot-cli
    devenv
    devcontainer
    podman-compose
    slirp4netns
  ];

  # set ssh-agent to cache keys for e.g. jupyterlab-git
  programs.ssh.startAgent = true;

  nix.settings.trusted-users = [ "zairex" ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
