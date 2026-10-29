{ config, pkgs, lib, unstable-pkgs, ... }:
let
  # Each container gets its own user namespace, so container root is an
  # unprivileged host uid instead of real root. Explicit ranges, not
  # `--userns=auto`: auto needs /etc/subuid and re-randomises every start.
  ns = n: let base = 200000 + n * 65536; in [
    "--uidmap=0:${toString base}:65536"
    "--gidmap=0:${toString base}:65536"
    "--security-opt=no-new-privileges"
  ];

  noCaps = [ "--cap-drop=ALL" ];

  # Container-to-container networks. The default podman bridge is flat — every
  # container could reach postgres — so each dependency gets its own network and
  # nothing else joins it. Caddy is unaffected: it reaches every app through its
  # published 127.0.0.1 port, not through these.
  #   db  postgres + its only two clients      cms  volto -> plone
  #   sim soitbeginsServer -> Simulation
  podmanNetworks = [ "db" "cms" "sim" ];

  # containers that sit on one of the above, so their units can wait for it
  networkedContainers = [
    "postgres" "postgrest" "logto" "plone" "volto"
    "soitbeginsServer" "soitbeginsSimulation"
  ];

  # Containers that wait on another to be *ready*, not merely started. `dependsOn`
  # orders the units, but postgres accepts connections seconds after its unit is
  # up — on 2026-09-12's reboot logto gave up on `pg` after 30s and exited 0, and
  # `Restart=on-failure` does not retry a clean exit. So these retry until the
  # thing they need answers.
  retryingContainers = [ "logto" "postgrest" "volto" "soitbeginsServer" ];

  # nginx images chown their cache dirs and bind :80 — tested minimum.
  nginxCaps = noCaps ++ [
    "--cap-add=CHOWN"
    "--cap-add=SETUID"
    "--cap-add=SETGID"
    "--cap-add=NET_BIND_SERVICE"
  ];
in
{
  imports = [
    ./znc.nix
    # Merge generated container settings with the explicit service units below.
    {
      systemd.services =
        lib.genAttrs (map (c: "podman-${c}") networkedContainers) (_: {
          after = [ "podman-networks.service" ];
          wants = [ "podman-networks.service" ];
        })
        // lib.genAttrs (map (c: "podman-${c}") retryingContainers) (_: {
          after = [ "podman-networks.service" ];
          wants = [ "podman-networks.service" ];
          serviceConfig = {
            Restart = lib.mkForce "always";
            RestartSec = "10s";
          };
        });
    }
  ];

  nixpkgs.overlays = [
    (_: _: {
      znc = unstable-pkgs.znc.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [ unstable-pkgs.libargon2 ];
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DWANT_ARGON=YES" ];
      });
    })
  ];

  services.znc =
    let
      modules = [ "savebuff @SAVEBUFF_KEY@" "log" ];
      networks = {
        libera = {
          Server = [ "irc.libera.chat +6697" ];
          TrustAllCerts = false;
          TrustPKI = true;
          LoadModule = modules ++ [ "sasl" ];
          Chan = lib.genAttrs [ "#vellumo" "#nixos" "##math" "#elm" ] (_: { });
        };
        quakenet = {
          AltNick = "Saireks";
          Server = [ "irc.quakenet.org 6667" ];
          LoadModule = modules;
          Chan = lib.genAttrs [ "#siilisota" "#91-syntyneet" "#alajärvi" ] (_: { });
        };
        ircnet = {
          AltNick = "Saireks";
          Server = [ "irc.atw-inter.net 6667" "irc.fu-berlin.de 6667" "irc.belwue.de 6667" ];
          LoadModule = modules;
          Chan = lib.genAttrs [ "#a47" "#hyrskytin" "#Tengen.fi" ] (_: { });
        };
      };
    in {
      enable = true;
      dataDir = "/var/data/znc";
      config = {
        MaxBufferSize = 500;
        Listener.l = {
          Host = "127.0.0.1";
          Port = 16667;
          IPv4 = true;
          IPv6 = false;
          SSL = false;
          AllowIRC = true;
          AllowWeb = false;
        };
        User.zairex = {
          Admin = false;
          Nick = "Zairex";
          AltNick = "Zairex_";
          Ident = "zairex";
          RealName = "Zairex";
          MultiClients = true;
          MaxNetworks = builtins.length (builtins.attrNames networks);
          ChanBufferSize = 500;
          QueryBufferSize = 500;
          AutoClearChanBuffer = false;
          AutoClearQueryBuffer = false;
          DenyLoadMod = true;
          DenySetNetwork = true;
          DenySetIdent = true;
          DenySetBindHost = true;
          DenySetRealName = true;
          Pass.password = {
            Method = "Argon2id";
            Hash = "@PASSWORD_HASH@";
          };
          Network = lib.mapAttrs (_: network: { IRCConnectEnabled = true; } // network) networks;
        };
      };
    };

  # Retain existing ownership; changing runtime does not require moving data.
  users.users.znc.isSystemUser = true;
  users.users.znc.uid = lib.mkForce 1510820;
  users.groups.znc.gid = lib.mkForce 1576253;
  systemd.services.znc.serviceConfig.LoadCredential = [
    "znc.json:/var/data/.secrets/znc.json"
    "sasl-libera.json:/var/data/.secrets/znc-libera.json"
  ];

  services.oidentd.enable = true;
  environment.etc."oidentd.conf".text = ''
    user "znc" {
        fport 6667 { force reply "${config.services.znc.config.User.zairex.Ident}" }
        fport 6697 { force reply "${config.services.znc.config.User.zairex.Ident}" }
    }
  '';
  systemd.services.oidentd.script = lib.mkForce ''
    ${pkgs.oidentd}/sbin/oidentd -C /etc/oidentd.conf -u oidentd -g nogroup
  '';

  systemd.services.znc-tailnet = {
    description = "Tailnet-only TLS ingress for ZNC";
    wantedBy = [ "multi-user.target" ];
    wants = [ "tailscaled.service" "znc.service" ];
    after = [ "tailscaled.service" "znc.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe config.services.tailscale.package} serve --tls-terminated-tcp=6697 tcp://127.0.0.1:${toString config.services.znc.config.Listener.l.Port}";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStopSec = "15s";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      UMask = "0077";
    };
  };

  environment.systemPackages = with pkgs; [
    (python3.withPackages (ps: with ps; [
      numpy
      requests
      flake8
      twine
    ]))
  ];

  boot.tmp.cleanOnBoot = true;
  zramSwap.enable = true;

  # Disk-backed swap as safety net (zram alone may OOM under load)
  swapDevices = [{
    device = "/var/swapfile";
    size = 2048;  # 2GB
  }];

  # Keep the system lean without being aggressive:
  # - GC weekly, but retain every generation from the last 30 days so we can
  #   always roll back a month's worth of rebuilds (current is always kept).
  # - Hard-link identical store paths to reclaim space.
  # - Bound the GRUB boot menu so it doesn't grow unbounded.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise = {
    automatic = true;
    dates = [ "weekly" ];
  };
  boot.loader.grub.configurationLimit = 20;

  # Prune unused podman images/networks weekly (--all also drops old image
  # versions left behind by podman-auto-update; running containers keep theirs).
  virtualisation.podman.autoPrune = {
    enable = true;
    dates = "weekly";
    flags = [ "--all" ];
  };

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

    virtualHosts."imdb.suvannossa.fi".extraConfig = ''
      reverse_proxy http://localhost:3014
    '';

    virtualHosts."raven.teekuningas.net".extraConfig = ''
      reverse_proxy http://localhost:3015
    '';

    virtualHosts."roolipeli.suvannossa.fi".extraConfig = ''
      reverse_proxy http://localhost:3016
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

      @classicapi {
        path_regexp classicapi ^/api/?(.*)$
      }

      handle @classicapi {
        rewrite  @classicapi /VirtualHostBase/https/kingofsweden.info:443/Plone/VirtualHostRoot/_vh_api/{http.regexp.classicapi.1}
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
        image = "plone/plone-backend:6.2.2.1";
        autoStart = true;
        user = "root";
        ports = [ "127.0.0.1:8080:8080" ];
        networks = [ "cms" ];
        extraOptions = ns 0;
        # `:idmap` maps ownership through the namespace — no chown needed.
        volumes = [ "/var/data/kingofsweden:/data:idmap" ];
      };
      volto = {
        image = "miaucloud-nixos/kingofsweden-volto:latest";
        user = "root";
        autoStart = true;
        ports = [ "127.0.0.1:3000:3000" ];
        networks = [ "cms" ];
        dependsOn = [ "plone" ];
        extraOptions = ns 1;
        environment = {
          COREPACK_INTEGRITY_KEYS = "0";
          RAZZLE_API_PATH = "https://kingofsweden.info";
          RAZZLE_INTERNAL_API_PATH = "http://plone:8080/Plone";
        };
      };
      soitbeginsFrontend = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-frontend:0.5.0";
        ports = [ "127.0.0.1:9011:9000" ];
        autoStart = true;
        # logs to a real file owned by www-data, not /dev/stdout like the
        # other nginx images, so container root needs DAC_OVERRIDE to write it
        extraOptions = ns 4 ++ nginxCaps ++ [ "--cap-add=DAC_OVERRIDE" ];
        environment = {
          SERVER_API = "wss://soitbegins.teekuningas.net/api";
        };
      };
      soitbeginsServer = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-server:0.5.0";
        ports = [ "127.0.0.1:8011:8765" ];
        autoStart = true;
        networks = [ "sim" ];
        dependsOn = [ "soitbeginsSimulation" ];
        extraOptions = ns 5;
        environment = {
          SIM_ZMQ_ADDR = "tcp://soitbeginsSimulation:5555";
        };
      };
      soitbeginsSimulation = {
        image = "ghcr.io/teekuningas/soitbegins/soitbegins-simulation:0.5.0";
        autoStart = true;
        networks = [ "sim" ];
        extraOptions = ns 6 ++ noCaps ++ [ "--memory=256m" "--memory-swap=384m" ];
      };
      postgres = {
        image = "docker.io/pgvector/pgvector:pg16";
        volumes = [ "/var/data/postgres_data:/var/lib/postgresql/data:idmap" ];
        autoStart = true;
        ports = [ "127.0.0.1:5432:5432" ];
        networks = [ "db" ];
        extraOptions = ns 9;
      };
      postgrest = {
        image = "docker.io/postgrest/postgrest:latest";
        autoStart = true;
        ports = [ "127.0.0.1:4001:4001" ];
        environment = {
          PGRST_SERVER_PORT = "4001";
        };
        networks = [ "db" ];
        dependsOn = [ "postgres" ];
        extraOptions = ns 10 ++ [ "--env-file=/var/data/.secrets/postgrest.env" ];
      };
      logto = {
        # To init the logto db, go inside container:
        # $ sudo podman run --env-file=/var/data/.secrets/logto.env --entrypoint="sh" -it svhd/logto:<version>
        # and run:
        # $ npm run cli db seed
        # Sometimes this is needed too:
        # $ npm run cli db alt deploy
        image = "docker.io/svhd/logto:1.25";
        ports = [ "127.0.0.1:3091:3091" "127.0.0.1:3092:3092" ];
        networks = [ "db" ];
        dependsOn = [ "postgres" ];
        extraOptions = ns 11 ++ [ "--env-file=/var/data/.secrets/logto.env" ];
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
        extraOptions = ns 12 ++ [ "--env-file=/var/data/.secrets/luontopeli.env" ];
        environment = { LUONTOPELI_HOST = "0.0.0.0"; };
      };
      vellubot = {
        image = "ghcr.io/teekuningas/vellubot/vellubot:v0.31.0";
        autoStart = true;
        extraOptions = ns 13 ++ [ "--env-file=/var/data/.secrets/vellubot.env" ];
        environment = {
          BOT_CHANNEL = "#vellumo";
          BOT_NICKNAME = "vellubot";
          BOT_SERVER = "irc.libera.chat";
          BOT_PORT = "6667";
          SETTINGS_FNAME = "/data/settings.json";
          AGENT_MEMORY_FNAME = "/data/agent_memory.json";
          AGENT_HISTORY_FNAME = "/data/agent_history.json";
          PARSER_SEEN_FNAME = "/data/parser_history.json";
          OPENAI_MAX_TOKENS_OUT = "2048";
          OPENAI_MODEL = "gpt-4o";
          URGE_TRIGGER_COST = "0.5";
          URGE_MSG_DIVISOR = "10";
          CHECK_INTERVAL = "300";
          LOG_LEVEL = "DEBUG";
        };
        volumes = [ "/var/data/vellubot:/data:idmap" ];
      };
      clothinv = {
        image = "ghcr.io/teekuningas/clothinv:0.3.2";
        ports = [ "127.0.0.1:3011:80" ];
        autoStart = true;
        extraOptions = ns 14 ++ nginxCaps;
      };
      jalkapallo = {
        image = "ghcr.io/teekuningas/jalkapallo:v2";
        ports = [ "127.0.0.1:3012:80" ];
        autoStart = true;
        extraOptions = ns 15 ++ nginxCaps;
      };
      sartre = {
        image = "ghcr.io/teekuningas/sartre:v0.41";
        ports = [ "127.0.0.1:3013:80" ];
        autoStart = true;
        extraOptions = ns 16 ++ nginxCaps;
      };
      imdbDemographics = {
        image = "ghcr.io/teekuningas/imdb-demographics:v1";
        ports = [ "127.0.0.1:3014:80" ];
        autoStart = true;
        extraOptions = ns 17 ++ nginxCaps;
      };
      ravenRiver = {
        # Source repo is private; the image is published public to GHCR by CI
        # on tag push (no pull auth needed, like the others above).
        image = "ghcr.io/teekuningas/soothing-raven-river:v10";
        ports = [ "127.0.0.1:3015:80" ];
        autoStart = true;
        extraOptions = ns 18 ++ nginxCaps;
      };
      rope = {
        image = "ghcr.io/teekuningas/rope:0.1.4";
        ports = [ "127.0.0.1:3016:80" ];
        autoStart = true;
        extraOptions = ns 19 ++ nginxCaps;
      };

    };
  };
  # oci-containers does not create networks, so do it here and make the
  # containers that need one wait for it.
  systemd.services.podman-networks = {
    description = "Create the podman networks used by oci-containers";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    script = lib.concatMapStringsSep "\n" (n:
      "${pkgs.podman}/bin/podman network exists ${n} || ${pkgs.podman}/bin/podman network create ${n}"
    ) podmanNetworks;
  };

  # Passwordless sudo for wheel users (SSH access is key-only).
  security.sudo.wheelNeedsPassword = false;

  system.stateVersion = "22.11";
}
