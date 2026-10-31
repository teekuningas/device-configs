{ pkgs, lib, inputs, unstable-pkgs, ... }:

let
  # Workaround: agent-sandbox commit 393fd15 blacklists emSign roots that
  # Mozilla already dropped from certdata.txt, causing buildcatrust to fail.
  raw-agent-sandbox = inputs.agent-sandbox.packages.${pkgs.stdenv.hostPlatform.system}.default;
  agent-sandbox = raw-agent-sandbox.override (orig: {
    pkgs = orig.pkgs.extend (final: prev: {
      # Use the host's podman: podman 6 from unstable can't read the
      # /etc/containers config written by the stable NixOS module (it honors
      # the rootful graphroot and rejects v1 registries.conf).
      podman = pkgs.podman;
      cacert = prev.cacert // {
        override = args: prev.cacert.override (
          let origArgs = if builtins.isFunction args then args prev.cacert else args;
          in origArgs // {
            blacklist = builtins.filter (name: !builtins.elem name [
              "emSign ECC Root CA - G3"
              "emSign Root CA - C1"
              "emSign ECC Root CA - C3"
            ]) (origArgs.blacklist or []);
          }
        );
      };
    });
  });
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
      github-copilot-cli = unstable-pkgs.github-copilot-cli;
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
