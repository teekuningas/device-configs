{
  description = "nixos configs";

  inputs = {
    nixpkgs-26-05.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-25-11.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    teepkgs.url = "github:teekuningas/pkgs";
    vasara-pkgs.url = "gitlab:vasara-bpm/pkgs";
    agent-sandbox.url = "github:teekuningas/agent-sandbox/main";
  };

  outputs =
    { self, nixpkgs-26-05, nixpkgs-25-11, nixpkgs-small, nixos-hardware, nixos-wsl, ... }@inputs:
    let
      # Fresh packages (e.g. AI agent CLIs) that shouldn't wait for the
      # stable release cycle.
      unstable-pkgs = import nixpkgs-small {
        system = "x86_64-linux";
        config.allowUnfree = true;
      };
    in {
      nixosConfigurations.procyon-nixos = nixpkgs-26-05.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs unstable-pkgs; };
        modules = [
          nixos-hardware.nixosModules.dell-precision-5490
          ./common/base.nix
          ./common/graphical.nix
          ./common/workstation.nix
          ./common/agents.nix
          ./procyon/hardware-configuration.nix
          ./procyon/configuration.nix
        ];
      };
      nixosConfigurations.miaucloud-nixos = nixpkgs-25-11.lib.nixosSystem {
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
      nixosConfigurations.miaudesk-nixos = nixpkgs-25-11.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs unstable-pkgs; };
        modules = [
          nixos-wsl.nixosModules.default
          ./common/base.nix
          ./common/graphical.nix
          ./common/workstation.nix
          ./common/agents.nix
          ./miaudesk/configuration.nix
        ];
      };
      nixosConfigurations.miaupad-nixos = nixpkgs-25-11.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit inputs unstable-pkgs; };
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
