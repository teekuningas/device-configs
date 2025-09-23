{
  nixpkgs.overlays = [
    (final: prev: {
      pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
        (pyfinal: pyprev: {
          llm = pyfinal.callPackage ./pkgs/llm { };
          llm-azure = pyfinal.callPackage ./pkgs/llm-azure { };
          condense-json = pyfinal.callPackage ./pkgs/condense-json { };
        })
      ];
    })
  ];
}
