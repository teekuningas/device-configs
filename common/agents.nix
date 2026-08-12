{ pkgs, lib, inputs, unstable-pkgs, ... }:

let
  # Host defaults for the agent-sandbox launcher.  Its CLI is the contract we
  # wrap: the flags are prepended, so any of them can still be flipped back for
  # a single run (agent-sandbox --workspace claude-code) and --help reports the
  # wrapped state.  Forwarding the host podman socket is opt-in upstream, so
  # --no-podman is no longer needed here.  Pick the agent per run:
  # `agent-sandbox claude-code`.  Load the image with `agent-sandbox-ctl load`.
  agent-sandbox = pkgs.symlinkJoin {
    name = "agent-sandbox";
    paths = [ inputs.agent-sandbox.packages.${pkgs.stdenv.hostPlatform.system}.default ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/agent-sandbox --add-flags "--podman-args=--add-host=jyu2401-62.tail5b278e.ts.net:100.79.190.50"
    '';
  };

  # The same sandbox idea rented rather than built: the box is a GitHub
  # Codespace, so the only local dependency is gh (bundled by its flake) and
  # the same launcher runs on a phone.  Its CLI is wrapped exactly like
  # agent-sandbox above — flags are prepended, so a host default can still be
  # flipped back for one run (agent-codespace --machine basicLinux32gb new) and
  # --help reports the wrapped state.  No flags are prepended yet; the upstream
  # defaults (basicLinux32gb, 60m idle, 24h retention) are the ones we want.
  agent-codespace = inputs.agent-codespace.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  # AI coding agent CLIs, kept fresh from nixos-unstable-small.
  nixpkgs.overlays = [
    (final: prev: {
      gemini-cli = unstable-pkgs.gemini-cli;
      opencode = unstable-pkgs.opencode;
      claude-code = unstable-pkgs.claude-code;
      pi-coding-agent = unstable-pkgs.pi-coding-agent;
      antigravity-cli = unstable-pkgs.antigravity-cli;
      agentsview = unstable-pkgs.callPackage (inputs.teepkgs + "/pkgs/agentsview") { };

      # Pinned copilot-cli binary release, newer than what nixpkgs carries.
      github-copilot-cli = unstable-pkgs.github-copilot-cli.overrideAttrs (oldAttrs: rec {
        version = "1.0.67";
        src = unstable-pkgs.fetchurl {
          url = "https://github.com/github/copilot-cli/releases/download/v${version}/copilot-linux-x64.tar.gz";
          hash = "sha256-xtJR3iDRRBXr1q8Av7ao44VAlLSfpJ+3898r+mT22zs=";
        };
        nativeBuildInputs = [ unstable-pkgs.makeBinaryWrapper unstable-pkgs.autoPatchelfHook ];
        buildInputs = [ unstable-pkgs.stdenv.cc.cc.lib ];
        sourceRoot = ".";
        installPhase = ''
          runHook preInstall
          install -Dm755 copilot $out/libexec/copilot
          runHook postInstall
        '';
        postInstall = ''
          makeWrapper $out/libexec/copilot $out/bin/copilot \
            --add-flags "--no-auto-update" \
            --prefix PATH : "${lib.makeBinPath [ unstable-pkgs.bash ]}"
        '';
      });
    })
  ];

  environment.systemPackages = with pkgs; [
    agent-codespace
    agent-sandbox
    agentsview
    antigravity-cli
    claude-code
    gemini-cli
    github-copilot-cli
    opencode
    pi-coding-agent
  ];
}
