{ config, lib, pkgs, inputs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "zairex";
  wsl.wslConf.network.hostname = "miaudesk-nixos";

  # To make the nvidia-container-toolkit work properly, useWindowsDriver is needed.
  wsl.useWindowsDriver = true;

  # Set up nix-ld to allow using non-native nvidia drivers.
  programs.nix-ld.enable = true;
  environment.variables = {
    # for nvidia-smi / cuda to work
    NIX_LD_LIBRARY_PATH = lib.mkForce (lib.makeLibraryPath [
      "/run/current-system/sw/share/nix-ld"
      "/usr/lib/wsl"
    ]);
  };

  # Note, to make nvidia work within containers, it was necessary to run nvidia-ctk.
  # To run nvidia-ctk, we needed nvidia-container-toolkit as a package (not just enabled hardware).
  # To get a nvidia-ctk without contaminating docker binary, a recent enough nixpkgs (e.g unstable) was needed.
  # The command to generate the cdi was:
  # $ nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml
  virtualisation.docker = {
    enable = true;
    daemon.settings.features.cdi = true;
  };
  environment.systemPackages = with pkgs; [
    (python312.withPackages (ps: with ps; [
      llm
      llm-ollama
      datasette
      jupyterlab
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
      (ps.callPackage "${inputs.teepkgs}/pkgs/ospeak/default.nix" {python3Packages = ps;})
      (ps.callPackage "${inputs.teepkgs}/pkgs/files-to-prompt/default.nix" {python3Packages = ps;})
    ]))
    (pkgs.buildFHSEnv {
      name = "uv";
      targetPkgs = pkgs: with pkgs; [ uv zlib ];
      runScript = "uv";
    })
    cudatoolkit
    nvidia-container-toolkit
    aider-chat
  ];

  # set ssh-agent to cache keys for e.g. jupyterlab-git
  programs.ssh.startAgent = true;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
