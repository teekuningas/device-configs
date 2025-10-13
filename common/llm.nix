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
    })
  ];
}
