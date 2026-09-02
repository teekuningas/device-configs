{ pkgs, lib, inputs, unstable-pkgs, ... }:

let
  agent-sandbox = inputs.agent-sandbox.packages.${pkgs.stdenv.hostPlatform.system}.default;
  agent-codespace = inputs.agent-codespace.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # AI coding agent CLIs, kept fresh from nixos-unstable-small.
  nixpkgs.overlays = [
    (final: prev: {
      opencode = unstable-pkgs.opencode;
      claude-code = unstable-pkgs.claude-code;
      pi-coding-agent = unstable-pkgs.pi-coding-agent;
      antigravity-cli = unstable-pkgs.antigravity-cli;
      agentsview = unstable-pkgs.callPackage (inputs.teepkgs + "/pkgs/agentsview") { };
    })
  ];

  environment.systemPackages = with pkgs; [
    agent-codespace
    agent-sandbox
    agentsview
    antigravity-cli
    claude-code
    github-copilot-cli
    opencode
    pi-coding-agent
  ];
}
