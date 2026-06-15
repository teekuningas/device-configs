{ lib, unstable-pkgs, ... }:
{
  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (pyfinal: pyprev: {
          llm = pyfinal.callPackage ./pkgs/llm { };
          llm-azure = pyfinal.callPackage ./pkgs/llm-azure { };
          llm-gemini = pyfinal.callPackage ./pkgs/llm-gemini { };
          condense-json = pyfinal.callPackage ./pkgs/condense-json { };
        })
      ];

      github-copilot-cli = unstable-pkgs.github-copilot-cli.overrideAttrs (oldAttrs: rec {
        version = "1.0.62";
        src = unstable-pkgs.fetchurl {
          url = "https://github.com/github/copilot-cli/releases/download/v${version}/copilot-linux-x64.tar.gz";
          hash = "sha256-y7SkAMhqGHYx3ta/gXeq358ohvylqeJ5mESRUaKM88g=";
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
}
