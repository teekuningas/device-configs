{ pkgs, ... }:
let
  soitbeginsFrontendVersion = "0.1.0";
  soitbeginsBackendVersion = "0.1.0";
  vellubotVersion = "0.18.0";
  chatWithGptVersion = "0.1.1";
  luontopeliVersion = "v4";
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
    gnumake
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.tmp.cleanOnBoot = true;
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

    # needed to fix podman dns
    trustedInterfaces = [ "podman0" ];
    interfaces.podman0.allowedUDPPorts = [ 53 ];

    # networking.firewall.allowedUDPPorts = [ ... ];
    # networking.firewall.allowedUDPPortRanges = [ { from = 32768; to = 61000; } ];
  };

  services.caddy = {
    enable = true;

    virtualHosts."luonto.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:5000
    '';

    virtualHosts."lobe.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:3210
    '';

    virtualHosts."soitbegins.teekuningas.net".extraConfig = ''
      @api {
        path /api
      }

      handle @api {
        uri strip_prefix /api
        reverse_proxy {
          to localhost:8011
        }
      }
      handle {
        reverse_proxy  {
          to localhost:9011
        }
      }
    '';

    virtualHosts."teehetki.teekuningas.net".extraConfig = ''
      basicauth * {
        syksy $2a$14$isHiXT5s3PtKmrYRii5cPuANI7Qj8LF853OR8pobUF32Hr0GJgYJS
      }

      @socket_io {
        path /socket.io/*
      }

      handle @socket_io {
        reverse_proxy {
          to localhost:5001
        }
      }
      handle {
        reverse_proxy  {
          to localhost:3001
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
    settings = {
      devices = {
        "miaupad" = { id = "JPKFCWF-SHUEUR6-QMGJDK5-UBLLUPJ-GQXUL46-NVJ44QR-GTG4HBQ-OJTAFQV"; };
        "miaudesk" = { id = "R5M6JCS-HGSMVJT-3PTMOEH-SETH3JI-77DKK55-2N2JL7U-XEXEVZS-ATCXSAV"; };
        "moto" = { id = "LVCM2CN-QSYEK6L-UK67Z3X-UPWTNF5-NS5GRH3-XFA5MSQ-W6PNFRL-P3WO7QO"; };
        "dip-reisen" = { id = "NRSG4QP-4TWK5XR-XOGNAWZ-N4FU3A4-PBE6DHU-Q2EDHTC-HA4YOTY-433PLQ7"; };
      };
      folders = {
        "obsidian_teekuningas" = {
          path = "/home/zairex/data/obsidian_teekuningas";
          devices = [ "miaupad" "moto" "dip-reisen" "miaudesk" ];
        };
      };
    };
  };

  services.openssh.enable = true;
  services.fail2ban = {
    enable = true;
    maxretry = 5;
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;

      defaultNetwork.settings = {
        dns_enabled = true;
      };
    };

    oci-containers.backend = "podman";
    oci-containers.containers = {
      plone = {
        image = "plone/plone-backend:6.0.9";
        autoStart = true;
        user = "root";
        extraOptions = [ "--net=host" ];
        volumes = [
         "/var/data/kingofsweden:/data"
        ];
      };
      volto = {
        image = "plone/plone-frontend:17.14.0";
        user = "root";
        autoStart = true;
        extraOptions = [ "--net=host" ];
        environment = {
          RAZZLE_API_PATH = "https://kingofsweden.info";
          RAZZLE_INTERNAL_API_PATH = "http://127.0.0.1:8080/Plone";
        };
      };
      teehetkiClient = {
        image = "ghcr.io/teekuningas/teehetki/teehetki-client:v4";
        ports = ["127.0.0.1:3001:3000"];
        autoStart = true;
        environment = {
          API_ADDRESS = "wss://teehetki.teekuningas.net";
        };
      };
      teehetkiServer = {
        image = "ghcr.io/teekuningas/teehetki/teehetki-server:v4";
        ports = ["127.0.0.1:5001:5000"];
        autoStart = true;
        environment = {
          API_ADDRESS = "https://api.openai.com";
          OPENAI_API_KEY = secrets.OPENAI_API_KEY;
        };
      };
      soitbeginsFrontend = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-frontend:${soitbeginsFrontendVersion}";
        ports = ["127.0.0.1:9011:9000"];
        autoStart = true;
        environment = {
          SERVER_API = "wss://soitbegins.teekuningas.net/api";
          MODEL_EARTH = "https://soitbegins.teekuningas.net/earth.zip";
        };
      };
      soitbeginsBackend = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-backend:${soitbeginsBackendVersion}";
        ports = ["127.0.0.1:8011:8765"];
        autoStart = true;
      };
      lobechat = {
        image = "docker.io/lobehub/lobe-chat:v1.6.0";
        ports = ["127.0.0.1:3210:3210"];
        autoStart = true;
      };
      luontopeli = {
        image = "ghcr.io/teekuningas/luontopeli/luontopeli:${luontopeliVersion}";
        ports = ["127.0.0.1:5000:5000"];
        autoStart = true;
        environment = {
          LUONTOPELI_APP_KEY = secrets.LUONTOPELI_APP_KEY;
          LUONTOPELI_API_TOKEN = secrets.LUONTOPELI_API_TOKEN;
          LUONTOPELI_HOST = "0.0.0.0";
        };
      };
      vellubot = {
        image = "ghcr.io/teekuningas/vellubot/vellubot:${vellubotVersion}";
        autoStart = true;
        environment = {
          BOT_CHANNEL = "#vellumo";
          BOT_NICKNAME = "vellubot";
          BOT_SERVER = "irc.libera.chat";
          BOT_PORT = "6667";
          BOT_SASL_PASSWORD = secrets.VELLUBOT_SASL_PASSWORD;
          SETTINGS_FNAME = "/data/settings.json";
          OPENAI_MAX_TOKENS_OUT = "1024";
          OPENAI_API_KEY = secrets.OPENAI_API_KEY;
          OPENAI_ORGANIZATION_ID = secrets.OPENAI_ORGANIZATION_ID;
        };
        volumes = [
         "/var/data/vellubot:/data"
        ];
      };
    };
  };
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "22.11";
}

