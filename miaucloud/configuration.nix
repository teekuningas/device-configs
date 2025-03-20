{ config, pkgs, lib, ... }:

{
  environment.systemPackages = with pkgs; [
    weechat
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
      9000 # Weechat
    ];

    # needed to fix podman dns
    trustedInterfaces = [ "podman0" ];
    interfaces.podman0.allowedUDPPorts = [ 53 ];

    # networking.firewall.allowedUDPPorts = [ ... ];
    # networking.firewall.allowedUDPPortRanges = [ { from = 32768; to = 61000; } ];
  };

  # Enable tailscale.
  # Currently must run manually "sudo tailscale up --advertise-exit-node".
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "both";
  };

  services.caddy = {
    enable = true;

    virtualHosts."luonto.teekuningas.net".extraConfig = ''
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

    virtualHosts."openwebui.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:8081
    '';

    virtualHosts."lobe.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:3210
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
        image = "plone/plone-backend:6.0.14";
        autoStart = true;
        user = "root";
        extraOptions = [ "--net=host" ];
        volumes = [
         "/var/data/kingofsweden:/data"
        ];
      };
      volto = {
        image = "plone/plone-frontend:18.4.0";
        user = "root";
        autoStart = true;
        extraOptions = [ "--net=host" ];
        environment = {
          COREPACK_INTEGRITY_KEYS="0";
          RAZZLE_API_PATH = "https://kingofsweden.info";
          RAZZLE_INTERNAL_API_PATH = "http://127.0.0.1:8080/Plone";
        };
      };
      teehetkiClient = {
        image = "ghcr.io/teekuningas/teehetki/teehetki-client:v10";
        ports = ["127.0.0.1:3001:3000"];
        autoStart = true;
        environment = {
          API_ADDRESS = "wss://teehetki.teekuningas.net";
        };
      };
      teehetkiServer = {
        image = "ghcr.io/teekuningas/teehetki/teehetki-server:v10";
        ports = ["127.0.0.1:5001:5000"];
        autoStart = true;
        extraOptions = [ "--env-file=/var/data/.secrets/teehetki_server.env" ];
        environment = {
          API_ADDRESS = "https://erpipehe-openai.openai.azure.com";
          LLM_MODEL = "gpt-4o-mini";
        };
      };
      soitbeginsFrontend = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-frontend:0.1.0";
        ports = ["127.0.0.1:9011:9000"];
        autoStart = true;
        environment = {
          SERVER_API = "wss://soitbegins.teekuningas.net/api";
          MODEL_EARTH = "https://soitbegins.teekuningas.net/earth.zip";
        };
      };
      soitbeginsBackend = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-backend:0.1.0";
        ports = ["127.0.0.1:8011:8765"];
        autoStart = true;
      };
      litellmProxy = {
        # To proxy openai-type requests to azure-like requests.
        image = "ghcr.io/berriai/litellm:main-latest";
        extraOptions = [ "--net=host" "--env-file=/var/data/.secrets/litellm.env" ];
        volumes = [
          "/var/data/litellm/config.yaml:/app/config.yaml"
        ];
        cmd = [
          "--config" "/app/config.yaml"
        ];
      };
      openWebui = {
        image = "ghcr.io/open-webui/open-webui:0.5.20";
        ports =  ["127.0.0.1:8081:8080"];
        extraOptions = [ "--net=host" "--env-file=/var/data/.secrets/openwebui.env" ];
        autoStart = true;
        environment = {
          PORT = "8081";
        };
        volumes = [
          "/var/data/openwebui_data:/app/backend/data"
        ];
      };
      lobechat = {
        # See: https://lobehub.com/docs/self-hosting/server-database/docker-compose
        # After postgres, logto and minio have been configured,
        # this should just work.
        image = "docker.io/lobehub/lobe-chat-database:1.73.0";
        ports = ["127.0.0.1:3210:3210"];
        extraOptions = [ "--net=host" "--env-file=/var/data/.secrets/lobechat.env" ];
        environment = {
          APP_URL = "https://lobe.teekuningas.net";
          S3_BUCKET = "lobe";
          S3_ENDPOINT = "https://s3-api.teekuningas.net";
          S3_PUBLIC_DOMAIN = "https://s3-api.teekuningas.net";
          S3_ENABLE_PATH_STYLE = "1";
          NEXT_AUTH_SSO_PROVIDERS = "logto";
          NEXTAUTH_URL = "https://lobe.teekuningas.net/api/auth";
          AUTH_LOGTO_ISSUER = "https://auth-api.teekuningas.net/oidc";

          ENABLED_OPENAI = "0";
          ENABLED_OLLAMA = "0";

          ENABLED_AZURE_OPENAI = "1";
          AZURE_API_VERSION = "2024-08-01-preview";
          AZURE_ENDPOINT = "https://erpipehe-openai.openai.azure.com";
          AZURE_MODEL_LIST = "gpt-4o,gpt-4o-mini";
        };
        autoStart = true;
      };
      postgres = {
        # See: https://lobehub.com/docs/self-hosting/server-database/docker-compose
        # Should not need any configuration.
        image = "docker.io/pgvector/pgvector:pg16";
        volumes = [
          "/var/data/postgres_data:/var/lib/postgresql/data"
        ];
        autoStart = true;
        extraOptions = [ "--net=host" "--env-file=/var/data/.secrets/postgres.env" ];
      };
      minio = {
        # See: https://lobehub.com/docs/self-hosting/server-database/docker-compose
        # Must create a bucket "lobe" through ui.
        image = "docker.io/minio/minio:latest";
        extraOptions = [ "--net=host" "--env-file=/var/data/.secrets/minio.env" ];
        volumes = [
          "/var/data/minio_data:/etc/minio/data"
        ];
        environment = {
          MINIO_DOMAIN = "s3-api.teekuningas.net";
          MINIO_API_CORS_ALLOW_ORIGIN = "https://lobe.teekuningas.net";
        };
        autoStart = true;
        cmd = [
          "server"
          "/etc/minio/data"
          "--address" "127.0.0.1:9090"
          "--console-address" "127.0.0.1:9091"
        ];
      };
      logto = {
        # See: https://lobehub.com/docs/self-hosting/server-database/docker-compose
        # To init the logto db, go inside container:
        # $ sudo podman run --net=host --env-file=/var/data/.secrets/logto.env --entrypoint="sh" -it svhd/logto:<version>
        # and run:
        # $ npm run cli db seed
        # Then navigate to ui and create app for lobe.
        # Sometimes this is needed too:
        # $ npm run cli db alt deploy
        image = "docker.io/svhd/logto:1.25";
        extraOptions = [ "--net=host" "--env-file=/var/data/.secrets/logto.env" ];
        environment = {
          TRUST_PROXY_HEADER = "1";
          ENDPOINT ="https://auth-api.teekuningas.net";
          ADMIN_ENDPOINT ="https://auth-ui.teekuningas.net";
          PORT = "3091";
          ADMIN_PORT = "3092";
        };
      };
      luontopeli = {
        image = "ghcr.io/teekuningas/luontopeli/luontopeli:v4";
        ports = ["127.0.0.1:5000:5000"];
        autoStart = true;
        extraOptions = [ "--env-file=/var/data/.secrets/luontopeli.env" ];
        environment = {
          LUONTOPELI_HOST = "0.0.0.0";
        };
      };
      vellubot = {
        image = "ghcr.io/teekuningas/vellubot/vellubot:0.19.2";
        autoStart = true;
        extraOptions = [ "--env-file=/var/data/.secrets/vellubot.env" ];
        environment = {
          BOT_CHANNEL = "#vellumo";
          BOT_NICKNAME = "vellubot";
          BOT_SERVER = "irc.libera.chat";
          BOT_PORT = "6667";
          SETTINGS_FNAME = "/data/settings.json";
          OPENAI_MAX_TOKENS_OUT = "1024";
          OPENAI_MODEL = "gpt-4o-mini";
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

