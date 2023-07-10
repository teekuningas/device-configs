{ pkgs, ... }:
let
  imagellmFrontendVersion = "v9";
  imagellmApiVersion = "v5";
  secretsFile = "/etc/nixos/secrets.nix";
  secrets =
    if builtins.pathExists secretsFile
    then import secretsFile
    else {};
in
{
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

    virtualHosts."imagellm.teekuningas.net".extraConfig = ''
      @api {
        path_regexp api ^/api/(.*)$
      }

      handle @api {
        uri strip_prefix /api
        reverse_proxy {
          to localhost:8001
        }
      }
      handle {
        reverse_proxy  {
          to localhost:9001
        }
      }
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

    virtualHosts."teekuningas.net".extraConfig = ''
      root * /var/data/static
      file_server
    '';

    virtualHosts."www.teekuningas.net".extraConfig = ''
      root * /var/data/static
      file_server
    '';

    virtualHosts."meggie.teekuningas.net".extraConfig = ''
      root * /var/data/meggie
      file_server
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

  systemd.services = {

    # Luontopeli systemd service
    luontopeli = {
      wantedBy = [ "multi-user.target" ];
      description = "Gunicorn-server to serve luontopeli";
      path = with pkgs; [ git ];
      serviceConfig = {
        User = "zairex";
        ExecStart = ''${pkgs.nix}/bin/nix develop /home/zairex/data/luontopeli --command gunicorn -w 2 --pythonpath /home/zairex/data/luontopeli "luontopeli:app"'';
      };
    };
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
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
        extraOptions = [ "--net=host" ];
        volumes = [
         "/var/data/kingofsweden:/data"
        ];
      };
      volto = {
        image = "plone/plone-frontend";
        user = "root";
        autoStart = true;
        extraOptions = [ "--net=host" ];
        environment = {
          RAZZLE_API_PATH = "https://kingofsweden.info";
          RAZZLE_INTERNAL_API_PATH = "http://127.0.0.1:8080/Plone";
        };
      };

      imagellmFrontend = {
        image = "ghcr.io/teekuningas/imagellm/imagellm-frontend:${imagellmFrontendVersion}";
        ports = ["127.0.0.1:9001:9000"];
        autoStart = true;
        environment = {
          API_ADDRESS = "https://imagellm.teekuningas.net/api";
        };
      };

      imagellmApi = {
        image = "ghcr.io/teekuningas/imagellm-api/imagellm-api:${imagellmApiVersion}";
        ports = ["127.0.0.1:8001:8001"];
        autoStart = true;
        environment = {
          OPENAI_API_KEY = secrets.OPENAI_API_KEY;
          GOOGLE_API_KEY = secrets.GOOGLE_API_KEY;
          GOOGLE_CX_ID = secrets.GOOGLE_CX_ID;
        };
      };
    };
  };

  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "22.11";
}

