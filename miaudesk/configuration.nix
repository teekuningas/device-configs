{ lib, pkgs, inputs, ... }:

{
  wsl.enable = true;
  wsl.defaultUser = "zairex";
  wsl.wslConf.network.hostname = "miaudesk-nixos";

  # To make the nvidia-container-toolkit work properly, useWindowsDriver is needed.
  wsl.useWindowsDriver = true;

  # Enable pulseaudio to get working audio.
  services.pulseaudio.enable = true;

  # WSL-specific library path overrides so nvidia-smi / cuda work with the
  # Windows-provided drivers (nix-ld itself is set up in common/workstation.nix).
  environment.variables = {
    NIX_LD_LIBRARY_PATH = lib.mkForce (lib.makeLibraryPath [
      "/run/current-system/sw/share/nix-ld"
      "/usr/lib/wsl"
    ]);
  };
  environment.sessionVariables.LD_LIBRARY_PATH = ["/run/opengl-driver/lib/"];

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

  # needed to fix podman dns (the rest of podman is in common/workstation.nix)
  virtualisation.podman.defaultNetwork.settings.dns_enabled = true;

  environment.systemPackages = with pkgs; [
    cudatoolkit
    nvidia-container-toolkit
    (callPackage (inputs.agent-sandbox + "/default.nix") {
      defaultAgent = "claude-code";
      defaultArgs = [ "--no-podman" "--no-ssh" "--no-workspace" ];
      extraAgents = [
        { name = "claude-code"; package = claude-code; command = [ "claude" ]; state = [ ".claude" ]; stateFiles = [ ".claude.json" ]; }
        { name = "copilot"; package = github-copilot-cli; command = [ "copilot" ]; state = [ ".copilot" ]; }
      ];
    })
  ];

  # set ssh-agent to cache keys for e.g. jupyterlab-git
  programs.ssh.startAgent = true;
  programs.ssh.extraConfig = ''
    AddKeysToAgent yes
  '';

  nix.settings.trusted-users = [ "zairex" ];

  system.stateVersion = "24.05";
}
