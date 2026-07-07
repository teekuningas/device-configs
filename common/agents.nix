{ pkgs, lib, inputs, unstable-pkgs, ... }:

{
  # The safepilot module provides the programs.safepilot options used below.
  imports = [ ./safepilot.nix ];

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
    agentsview
    antigravity-cli
    claude-code
    gemini-cli
    github-copilot-cli
    opencode
    pi-coding-agent
  ];

  # Build-time selection of what gets installed inside the safepilot
  # container; the runtime mount options (defaultArgs) are per-host.
  programs.safepilot = {
    enable = true;
    withCopilot = true;
    withGemini = true;
    withOpencode = true;
    withClaudeCode = true;
    withPi = true;
  };
}
