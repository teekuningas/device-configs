{ pkgs, ... }: {
  imports = [
    ./hardware-configuration.nix
    ./networking.nix # generated at runtime by nixos-infect
    ./users.nix
  ];

  environment.systemPackages = with pkgs; [
    vim
    tmux
    git
    powertop
    htop
    wget
    curl
    weechat
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.cleanTmpDir = true;
  zramSwap.enable = true;

  # Set your time zone.
  time.timeZone = "Europe/Helsinki";

  # Select internationalisation properties.
  i18n.defaultLocale = "fi_FI.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "fi";
  };

  networking.hostName = "miaucloud-nixos";
  networking.domain = "";
  networking.firewall = {
    # enable the firewall
    enable = true;

    allowedTCPPorts = [
      22 # SSH
      80 # HTTP
      443 # HTTPS
      9000 # Weechat
      22000 # Syncthing
    ];
    allowedUDPPorts = [
      21027 # Syncthing
      22000 # Syncthing
    ];

    # networking.firewall.allowedUDPPorts = [ ... ];
    # networking.firewall.allowedUDPPortRanges = [ { from = 32768; to = 61000; } ];
  };

  services.caddy = {
    enable = true;
    virtualHosts."luonto.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:8000
    '';

    virtualHosts."kingofsweden.info".extraConfig = ''

      @apiplone {
        path_regexp apiplone ^/\+\+api\+\+/(.*)$
      }

      handle @apiplone {
        rewrite  @apiplone /VirtualHostBase/https/kingofsweden.info:443/Plone/++api++/VirtualHostRoot/{http.regexp.apiplone.1}
        reverse_proxy {
          to localhost:8080
        }
      }
      handle {
        reverse_proxy  {
          to localhost:3000
        }
      }
    '';
  };

  services.syncthing = {
    enable = true;
    user = "zairex";
    dataDir = "/home/zairex/data/obsidian_teekuningas";
    configDir = "/home/zairex/.config/syncthing";
    overrideDevices = true;
    overrideFolders = true;
    devices = {
      "miaupad" = { id = "JPKFCWF-SHUEUR6-QMGJDK5-UBLLUPJ-GQXUL46-NVJ44QR-GTG4HBQ-OJTAFQV"; };
      "moto" = { id = "LVCM2CN-QSYEK6L-UK67Z3X-UPWTNF5-NS5GRH3-XFA5MSQ-W6PNFRL-P3WO7QO"; };
      "dip-reisen" = { id = "NRSG4QP-4TWK5XR-XOGNAWZ-N4FU3A4-PBE6DHU-Q2EDHTC-HA4YOTY-433PLQ7"; };
    };
    folders = {
      "obsidian_teekuningas" = {
        path = "/home/zairex/data/obsidian_teekuningas";
        devices = [ "miaupad" "moto" "dip-reisen" ];
      };
    };
  };

  services.openssh.enable = true;

  systemd.services.luontopeli = {
    wantedBy = [ "multi-user.target" ];
    description = "Gunicorn-server to serve luontopeli";
    path = with pkgs; [ git ];
    serviceConfig = {
      User = "zairex";
      ExecStart = ''${pkgs.nix}/bin/nix develop /home/zairex/data/luontopeli --command gunicorn -w 2 --pythonpath /home/zairex/data/luontopeli "luontopeli:app"'';
    };
  };

  virtualisation = {
    podman = {
      enable = true;

      # Create a `docker` alias for podman, to use it as a drop-in replacement
      dockerCompat = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.dnsname.enable = true;

      # For Nixos version > 22.11
      # defaultNetwork.settings = {
      #  dns_enabled = true;
      # };
    };

    oci-containers.backend = "podman";
    oci-containers.containers = {
      plone = {
        image = "plone/plone-backend";
        autoStart = true;
        user = "root";
        ports = [ "127.0.0.1:8080:8080" ];
        volumes = [
         "/home/zairex/data/kingofsweden/var:/data"
       ];
      };
      volto = {
        image = "plone/plone-frontend";
        user = "root";
        autoStart = true;
        ports = [ "127.0.0.1:3000:3000" ];
        environment = {
          RAZZLE_API_PATH = "https://kingofsweden.info";
        };
      };
    };
  };

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "22.11";
}

