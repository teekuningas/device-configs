{ options, pkgs, ... }:

{
  # Package simonw's llm CLI and plugins into the python package sets,
  # for use in the python environment below.
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

  # Rootless podman with docker compatibility.
  virtualisation = {
    containers.containersConf.settings.network.default_rootless_network_cmd = "slirp4netns";
    podman = {
      enable = true;
      dockerCompat = true;
    };
  };
  # To mitigate problem with "trigger-limit-hit" for podman.service
  systemd.user.sockets.podman.socketConfig = {
    TriggerLimitIntervalSec = "10s";
    TriggerLimitBurst = 1000;
  };
  # To remove problem of missing newuidmap binary for podman.service
  systemd.user.services.podman.path = [ "/run/wrappers/" ];

  # Set up nix-ld to allow running non-nix binaries (e.g. installed by uv).
  programs.nix-ld = {
    enable = true;
    libraries = options.programs.nix-ld.libraries.default ++ (
      with pkgs; [
        dbus
        fontconfig
        freetype
        glib
        libGL
        libxkbcommon
        xorg.libxcb
        xorg.libX11
        xorg.xcbutilwm
        xorg.xcbutilimage
        xorg.xcbutilkeysyms
        xorg.xcbutilrenderutil
      ]
    );
  };

  environment.systemPackages = with pkgs; [
    (python313.withPackages (ps: with ps; [
      numpy
      cryptography
      requests
      flake8
      twine
      jupyterlab
      jupytext
      ipywidgets
      matplotlib
      scipy
      pandas
      seaborn
      statsmodels
      rasterio
      geopandas
      folium
      llm
      llm-azure
    ]))
    uv
    nodejs
    devenv
    gh
    podman-compose
    slirp4netns
    (chromium.override {
      commandLineArgs = [
        "--remote-debugging-port=9222"
      ];
    })
  ];
}
