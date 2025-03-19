{
  description = "nixos configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    teepkgs.url = "github:teekuningas/pkgs";
  };

  outputs = { self, nixpkgs, nixpkgs-small, nixos-hardware, nixos-wsl, ... }@inputs: {
    nixosConfigurations.procyon-nixos = nixpkgs-small.lib.nixosSystem {
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
    nixosConfigurations.miaucloud-nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./common/base.nix
        ./common/python.nix
        ./miaucloud/configuration.nix
        ./miaucloud/hardware-configuration.nix
        ./miaucloud/networking.nix
        ./miaucloud/users.nix
      ];
    };
    nixosConfigurations.miaudesk-nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        nixos-wsl.nixosModules.default
        ./common/base.nix
        ./common/graphical.nix
        ./common/python.nix
        ./miaudesk/configuration.nix
      ];
    };
    nixosConfigurations.miaupad-nixos = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        ./common/base.nix
        ./common/graphical.nix
        ./common/python.nix
        ./miaupad/configuration.nix
        ./miaupad/hardware-configuration.nix
      ];
    };
  };
}
