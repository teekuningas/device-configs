{
  description = "nixos configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    teepkgs.url = "github:teekuningas/pkgs";
  };

  outputs = { self, nixpkgs, nixos-hardware, ... }@inputs: {
    nixosConfigurations.procyon-nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        nixos-hardware.nixosModules.dell-precision-5490
        ./common/base.nix
        ./common/graphical.nix
        ./common/python.nix
        ./procyon/hardware-configuration.nix
        ./procyon/configuration.nix
      ];
    };
  };
}
