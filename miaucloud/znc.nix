{
  config,
  lib,
  pkgs,
  ...
}:
let
  base = 200000 + 20 * 65536;
  uid = base + 100;
  gid = base + 65533;
  state = "/var/data/znc";
  secrets = "/var/data/.secrets/znc.json";
  image = "docker.io/library/znc@sha256:5feabfc6dbf5504d3620cd9142e5bd85b338dc7605c4e0bc5c9025e3eab8c9f0";
  template = pkgs.writeText "znc.conf.in" ''
    Version = 1.10.3
    MaxBufferSize = 500
    <Listener loopback>
        Host = 127.0.0.1
        Port = 16667
        IPv4 = true
        IPv6 = false
        SSL = false
        AllowIRC = true
        AllowWeb = false
    </Listener>
    <User zairex>
        Admin = false
        Nick = Zairex
        AltNick = Zairex_
        Ident = zairex
        RealName = Zairex
        MultiClients = true
        MaxNetworks = 3
        ChanBufferSize = 500
        QueryBufferSize = 500
        AutoClearChanBuffer = false
        AutoClearQueryBuffer = false
        DenyLoadMod = true
        DenySetNetwork = true
        DenySetIdent = true
        DenySetBindHost = true
        DenySetRealName = true
        <Pass password>
            Method = Argon2id
            Hash = @PASSWORD_HASH@
        </Pass>
    ${lib.concatMapStringsSep "\n"
      (network: ''
        <Network ${network}>
            IRCConnectEnabled = false
            LoadModule = savebuff @SAVEBUFF_KEY@
        </Network>
      '')
      [
        "libera"
        "quakenet"
        "ircnet"
      ]
    }
    </User>
  '';
in
{
  users.groups.znc.gid = gid;
  users.users.znc = {
    isSystemUser = true;
    inherit uid;
    group = "znc";
    home = "/var/empty";
    shell = "${pkgs.shadow}/bin/nologin";
    autoSubUidGidRange = false;
  };

  environment.etc."oidentd.conf".text = ''
    user "znc" {
        fport 6667 { force reply "zairex" }
        fport 6697 { force reply "zairex" }
    }
  '';
  systemd.services.oidentd.script = lib.mkForce ''
    ${pkgs.oidentd}/sbin/oidentd -C /etc/oidentd.conf -u oidentd -g nogroup
  '';

  systemd.tmpfiles.rules = [
    "d ${state} 0700 ${toString uid} ${toString gid} -"
    "d ${state}/configs 0700 ${toString uid} ${toString gid} -"
  ];

  virtualisation.oci-containers.containers.znc = {
    inherit image;
    user = "100:65533";
    volumes = [ "${state}:/znc-data" ];
    extraOptions = [
      "--uidmap=0:${toString base}:65536"
      "--gidmap=0:${toString base}:65536"
      "--network=host"
      "--read-only"
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges"
      "--tmpfs=/tmp:rw,nosuid,nodev,size=16m,mode=1777"
      "--memory=256m"
      "--pids-limit=64"
    ];
  };
  systemd.services.podman-znc = {
    after = [ "systemd-tmpfiles-setup.service" ];
    restartTriggers = [
      template
      ./scripts/render_znc.py
    ];
    preStart = ''
      ${pkgs.python3}/bin/python3 ${./scripts/render_znc.py} ${template} ${secrets} ${state}/configs/znc.conf ${toString uid} ${toString gid}
    '';
    serviceConfig = {
      Restart = lib.mkForce "always";
      RestartSec = "10s";
      UMask = "0077";
    };
  };

  systemd.services.znc-tailnet = {
    description = "Tailnet-only TLS ingress for ZNC";
    wantedBy = [ "multi-user.target" ];
    wants = [
      "tailscaled.service"
      "podman-znc.service"
    ];
    after = [
      "tailscaled.service"
      "podman-znc.service"
    ];
    serviceConfig = {
      ExecStart = "${lib.getExe config.services.tailscale.package} serve --tls-terminated-tcp=6697 tcp://127.0.0.1:16667";
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
}
