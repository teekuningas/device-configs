{ config, options, lib, pkgs, ... }:
{
  options.tee-options = {
    python-packages = with lib; mkOption {
      type = with types; listOf str;
      description = "List of python packages passed to the system python env";
    };
  };

  config = {
    tee-options.python-packages = ["numpy" "requests" "flake8"];
    environment.systemPackages = with pkgs; [
      (python312.withPackages (ps: builtins.map (pkgName: ps.${pkgName}) config.tee-options.python-packages))
    ];
  };
}
