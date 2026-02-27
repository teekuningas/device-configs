{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    weechat
    (python312.withPackages (ps: with ps; [
      numpy
      requests
      flake8
      twine
    ]))
  ];

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
      113 # Oidentd
    ];

    # needed to fix podman dns
    trustedInterfaces = [ "podman0" ];
    interfaces.podman0.allowedUDPPorts = [ 53 ];

    # networking.firewall.allowedUDPPorts = [ ... ];
    # networking.firewall.allowedUDPPortRanges = [ { from = 32768; to = 61000; } ];
  };

  # Enable oidentd for IRCNet
  services.oidentd.enable = true;

  # Enable tailscale.
  # Currently must run manually "sudo tailscale up --advertise-exit-node".
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  services.caddy = {
    enable = true;

    virtualHosts."vaatteet.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:3011
    '';

    virtualHosts."clothinv-postgrest.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:4001
    '';

    virtualHosts."pallo.suvannossa.fi".extraConfig = ''
      reverse_proxy http://localhost:3012
    '';

    virtualHosts."sartre.suvannossa.fi".extraConfig = ''
      reverse_proxy http://localhost:3013
    '';

    virtualHosts."luonto.suvannossa.fi".extraConfig = ''
      reverse_proxy http://localhost:5000
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
        plonerules $2a$14$OpYh7I1bR4Uq.c6YAk1S7O1RBxK/1Z2fMPmFRciv72XGdQNmOKpxO
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

    virtualHosts."suvannossa.fi".extraConfig = ''
      root * /var/data/static/suvannossa.fi
      file_server
    '';

    virtualHosts."www.suvannossa.fi".extraConfig = ''
      root * /var/data/static/suvannossa.fi
      file_server
    '';

    virtualHosts."teekuningas.net".extraConfig = ''
      root * /var/data/static/teekuningas.net
      file_server
    '';

    virtualHosts."www.teekuningas.net".extraConfig = ''
      root * /var/data/static/teekuningas.net
      file_server
    '';

    virtualHosts."meggie.teekuningas.net".extraConfig = ''
      root * /var/data/meggie
      file_server
    '';

    virtualHosts."openwebui.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:8081
    '';

    virtualHosts."s3-api.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:9090
    '';

    virtualHosts."s3-ui.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:9091
    '';

    virtualHosts."auth-api.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:3091
    '';

    virtualHosts."auth-ui.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:3092
    '';
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "prohibit-password";  # Allow root login with keys only
      KbdInteractiveAuthentication = false;
    };
  };
  services.fail2ban = {
    enable = true;
    maxretry = 5;
  };

  systemd.timers."data-backup" = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      Unit = "data-backup.service";
    };
  };
  systemd.services."data-backup" = {
    script = builtins.readFile ./scripts/backup_data.sh;

    path = with pkgs; [
      podman
      gzip
      rsync
      gnutar
    ];

    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;

      defaultNetwork.settings = { dns_enabled = true; };
    };

    oci-containers.backend = "podman";
    oci-containers.containers = {
      plone = {
        image = "plone/plone-backend:6.0.14";
        autoStart = true;
        user = "root";
        extraOptions = [ "--net=host" ];
        volumes = [ "/var/data/kingofsweden:/data" ];
      };
      volto = {
        image = "plone/plone-frontend:18.4.0";
        user = "root";
        autoStart = true;
        extraOptions = [ "--net=host" ];
        environment = {
          COREPACK_INTEGRITY_KEYS = "0";
          RAZZLE_API_PATH = "https://kingofsweden.info";
          RAZZLE_INTERNAL_API_PATH = "http://127.0.0.1:8080/Plone";
        };
      };
      teehetkiClient = {
        image = "ghcr.io/teekuningas/teehetki/teehetki-client:v10";
        ports = [ "127.0.0.1:3001:3000" ];
        autoStart = true;
        environment = { API_ADDRESS = "wss://teehetki.teekuningas.net"; };
      };
      teehetkiServer = {
        image = "ghcr.io/teekuningas/teehetki/teehetki-server:v10";
        ports = [ "127.0.0.1:5001:5000" ];
        autoStart = true;
        extraOptions = [ "--env-file=/var/data/.secrets/teehetki_server.env" ];
        environment = {
          API_ADDRESS = "https://erpipehe-openai.openai.azure.com";
          LLM_MODEL = "gpt-4o-mini";
        };
      };
      soitbeginsFrontend = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-frontend:0.1.0";
        ports = [ "127.0.0.1:9011:9000" ];
        autoStart = true;
        environment = {
          SERVER_API = "wss://soitbegins.teekuningas.net/api";
          MODEL_EARTH = "https://soitbegins.teekuningas.net/earth.zip";
        };
      };
      soitbeginsBackend = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-backend:0.1.0";
        ports = [ "127.0.0.1:8011:8765" ];
        autoStart = true;
      };
      litellmProxy = {
        # To proxy openai-type requests to azure-like requests.
        image = "ghcr.io/berriai/litellm:main-latest";
        extraOptions =
          [ "--net=host" "--env-file=/var/data/.secrets/litellm.env" ];
        volumes = [ "/var/data/litellm/config.yaml:/app/config.yaml" ];
        cmd = [ "--config" "/app/config.yaml" ];
      };
      openWebui = {
        image = "miaucloud-nixos/open-webui:0.7.2";
        ports = [ "127.0.0.1:8081:8080" ];
        extraOptions =
          [ "--net=host" "--env-file=/var/data/.secrets/openwebui.env" ];
        autoStart = true;
        environment = { PORT = "8081"; };
        volumes = [ "/var/data/openwebui_data:/app/backend/data" ];
      };
      postgres = {
        image = "docker.io/pgvector/pgvector:pg16";
        volumes = [ "/var/data/postgres_data:/var/lib/postgresql/data" ];
        autoStart = true;
        extraOptions =
          [ "--net=host" ];
      };
      postgrest = {
        image = "docker.io/postgrest/postgrest:latest";
        autoStart = true;
        environment = {
          PGRST_SERVER_PORT = "4001";
        };
        extraOptions =
          [ "--net=host" "--env-file=/var/data/.secrets/postgrest.env" ];
      };
      logto = {
        # To init the logto db, go inside container:
        # $ sudo podman run --net=host --env-file=/var/data/.secrets/logto.env --entrypoint="sh" -it svhd/logto:<version>
        # and run:
        # $ npm run cli db seed
        # Sometimes this is needed too:
        # $ npm run cli db alt deploy
        image = "docker.io/svhd/logto:1.25";
        extraOptions =
          [ "--net=host" "--env-file=/var/data/.secrets/logto.env" ];
        environment = {
          TRUST_PROXY_HEADER = "1";
          ENDPOINT = "https://auth-api.teekuningas.net";
          ADMIN_ENDPOINT = "https://auth-ui.teekuningas.net";
          PORT = "3091";
          ADMIN_PORT = "3092";
        };
      };
      luontopeli = {
        image = "ghcr.io/teekuningas/luontopeli/luontopeli:v4";
        ports = [ "127.0.0.1:5000:5000" ];
        autoStart = true;
        extraOptions = [ "--env-file=/var/data/.secrets/luontopeli.env" ];
        environment = { LUONTOPELI_HOST = "0.0.0.0"; };
      };
      vellubot = {
        image = "ghcr.io/teekuningas/vellubot/vellubot:v0.20.0";
        autoStart = true;
        extraOptions = [ "--env-file=/var/data/.secrets/vellubot.env" ];
        environment = {
          BOT_CHANNEL = "#vellumo";
          BOT_NICKNAME = "vellubot";
          BOT_SERVER = "irc.libera.chat";
          BOT_PORT = "6667";
          SETTINGS_FNAME = "/data/settings.json";
          OPENAI_MAX_TOKENS_IN = "2048";
          OPENAI_MAX_TOKENS_OUT = "1024";
          OPENAI_MODEL = "gpt-4o";
        };
        volumes = [ "/var/data/vellubot:/data" ];
      };
      clothinv = {
        image = "ghcr.io/teekuningas/clothinv:0.3.2";
        ports = [ "127.0.0.1:3011:80" ];
        autoStart = true;
      };
      jalkapallo = {
        image = "ghcr.io/teekuningas/jalkapallo:v2";
        ports = [ "127.0.0.1:3012:80" ];
        autoStart = true;
      };
      sartre = {
        image = "ghcr.io/teekuningas/sartre:v0.41";
        ports = [ "127.0.0.1:3013:80" ];
        autoStart = true;
      };
    };
  };
  # Require password for sudo (security hardening)
  # Uncomment the line below if you need passwordless sudo
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "22.11";
}
