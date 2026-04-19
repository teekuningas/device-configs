{ config, pkgs, lib, ... }:

let
  cfg = config.programs.safepilot;
in {
  options.programs.safepilot = {
    enable = lib.mkEnableOption "safepilot sandboxed AI coding environment";

    copilotSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include github-copilot-cli in the container and mount ~/.copilot for auth.";
    };

    geminiSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include gemini-cli in the container, mount ~/.gemini, and pass Gemini auth tokens.";
    };

    gitSupport = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Include git and gh in the container, mount ~/.gitconfig, and pass git author env vars.";
    };

    opencodeSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include opencode in the container and mount ~/.local/share/opencode + ~/.config/opencode for auth and config.";
    };

    mcpSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include nodejs in the container and mount ~/.npm for running node-based MCP servers.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: prev: {
        safepilot = final.callPackage ./pkgs/safepilot {
          copilotSupport       = cfg.copilotSupport;
          geminiSupport        = cfg.geminiSupport;
          gitSupport           = cfg.gitSupport;
          opencodeSupport      = cfg.opencodeSupport;
          mcpSupport           = cfg.mcpSupport;
        };
      })
    ];

    environment.systemPackages = [ pkgs.safepilot ];
  };
}
