{
  description = "nixos configs";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-25-05.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";
    teepkgs.url = "github:teekuningas/pkgs";
    vasara-pkgs.url = "gitlab:vasara-bpm/pkgs";
  };

  outputs =
    { self, nixpkgs, nixpkgs-25-05, nixpkgs-small, nixos-hardware, nixos-wsl, ... }@inputs:
    let
      unstable-pkgs-for = system: import nixpkgs-small {
        inherit system;
        config.allowUnfree = true;
      };
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in {
      nixosConfigurations.procyon-nixos = nixpkgs-25-05.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; unstable-pkgs = unstable-pkgs-for "x86_64-linux"; };
        modules = [
          nixos-hardware.nixosModules.dell-precision-5490
          ./common/base.nix
          ./common/graphical.nix
          ./common/llm.nix
          ./common/safepilot.nix
          ./procyon/hardware-configuration.nix
          ./procyon/configuration.nix
        ];
      };
      nixosConfigurations.miaucloud-nixos = nixpkgs-25-05.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; };
        modules = [
          ./common/base.nix
          ./miaucloud/configuration.nix
          ./miaucloud/hardware-configuration.nix
          ./miaucloud/networking.nix
          ./miaucloud/users.nix
        ];
      };
      nixosConfigurations.miaudesk-nixos = nixpkgs-25-05.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; unstable-pkgs = unstable-pkgs-for "x86_64-linux"; };
        modules = [
          nixos-wsl.nixosModules.default
          ./common/base.nix
          ./common/graphical.nix
          ./common/llm.nix
          ./common/safepilot.nix
          ./miaudesk/configuration.nix
        ];
      };
      nixosConfigurations.miaupad-nixos = nixpkgs-25-05.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs; unstable-pkgs = unstable-pkgs-for "x86_64-linux"; };
        modules = [
          nixos-hardware.nixosModules.lenovo-thinkpad-t440s
          ./common/base.nix
          ./common/graphical.nix
          ./miaupad/configuration.nix
          ./miaupad/hardware-configuration.nix
        ];
      };
    };
}
