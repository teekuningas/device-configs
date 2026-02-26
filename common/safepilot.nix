{ pkgs, lib, ... }:

{
  nixpkgs.overlays = [
    (final: prev: {
      safepilot = final.callPackage ./pkgs/safepilot { };
    })
  ];

  environment.systemPackages = [ pkgs.safepilot ];
}
