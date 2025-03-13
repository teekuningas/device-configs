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
    NIX_LD_LIBRARY_PATH = lib.mkForce (lib.makeLibraryPath [
      "/run/current-system/sw/share/nix-ld"
      "/usr/lib/wsl"
    ]);
    OLLAMA_HOST = "https://jyu2401-62.tail5b278e.ts.net/ollamapi";
    OLLAMA_API_BASE="https://jyu2401-62.tail5b278e.ts.net/ollamapi";
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

  tee-options.python-packages = [ "llm" "llm-ollama" "aider-chat"];

  environment.systemPackages = with pkgs; [
    inputs.teepkgs.packages."${pkgs.system}".files-to-prompt
    (pkgs.buildFHSEnv {
      name = "uv";
      targetPkgs = pkgs: with pkgs; [ uv zlib ];
      runScript = "uv";
    })
    cudatoolkit
    nvidia-container-toolkit
  ];

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "24.05"; # Did you read the comment?
}
