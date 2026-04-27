{ config, pkgs, lib, ... }:

let
  cfg = config.programs.safepilot;
in {
  options.programs.safepilot = {
    enable = lib.mkEnableOption "safepilot sandboxed AI coding environment";

    defaultArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Default arguments to pass to the safepilot launcher (e.g. [ \"--git\" \"--ssh\" ]). Use --plain to ignore these.";
    };

    withCopilot = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include github-copilot-cli in the container.";
    };

    withGemini = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include gemini-cli in the container.";
    };

    withOpencode = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include opencode in the container.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.overlays = [
      (final: prev: {
        safepilot = final.callPackage ./pkgs/safepilot {
          defaultArgs  = cfg.defaultArgs;
          withCopilot  = cfg.withCopilot;
          withGemini   = cfg.withGemini;
          withOpencode = cfg.withOpencode;
        };
      })
    ];

    environment.systemPackages = [ pkgs.safepilot ];
  };
}
