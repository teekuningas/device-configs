{ pkgs, host }:
let
  evaluate =
    extra:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../znc.nix
        {
          boot.isContainer = true;
          system.stateVersion = "26.05";
        }
      ]
      ++ extra;
    }).config;
  disabled = evaluate [ ];
  friend = evaluate [
    {
      services.znc = {
        enable = true;
        config.User.friend = {
          Nick = "Friend";
          MaxNetworks = 2;
          Pass.password = {
            Method = "Argon2id";
            Hash = "@PASSWORD_HASH@";
          };
          Network = {
            example = {
              Server = [ "irc.example.net +6697" ];
              LoadModule = [
                "savebuff @SAVEBUFF_KEY@"
                "log"
                "sasl"
              ];
              Chan."#example" = { };
            };
            other = {
              Server = [ "irc.other.example +6697" ];
              LoadModule = [
                "savebuff @SAVEBUFF_KEY@"
                "log"
              ];
            };
          };
        };
      };
      systemd.services.znc.serviceConfig.LoadCredential = [
        "znc.json:/run/secrets/friend.json"
        "sasl-example.json:/run/secrets/example.json"
      ];
    }
  ];
in
assert !disabled.services.znc.enable;
assert !(disabled.systemd.services ? znc) && !(disabled.users.users ? znc);
assert host.services.znc.enable && !host.services.znc.mutable;
assert !host.services.znc.useLegacyConfig;
assert !(host.virtualisation.oci-containers.containers ? znc);
assert host.users.users.znc.uid == 1510820 && host.users.groups.znc.gid == 1576253;
assert !friend.services.znc.mutable && !friend.services.znc.useLegacyConfig;
assert !friend.services.tailscale.enable && !friend.services.oidentd.enable;
assert friend.networking.firewall.allowedTCPPorts == [ ];
assert friend.services.znc.dataDir == "/var/lib/znc";
assert friend.users.users.znc.uid == friend.ids.uids.znc;
assert friend.users.groups.znc.gid == friend.ids.gids.znc;
assert friend.nixpkgs.overlays == [ ];
assert builtins.attrNames friend.services.znc.config.User == [ "friend" ];
assert
  friend.systemd.services.znc.serviceConfig.LoadCredential == [
    "znc.json:/run/secrets/friend.json"
    "sasl-example.json:/run/secrets/example.json"
  ];
pkgs.runCommand "znc-native-tests"
  {
    nativeBuildInputs = [ pkgs.python3 ];
    template = host.services.znc.configFile;
    znc = host.systemd.services.znc.serviceConfig.ExecStart;
    friendTemplate = friend.services.znc.configFile;
    friendPreStart = friend.systemd.services.znc.preStart;
  }
  ''
    PYTHONPATH=${./.} python3 ${./test_render_znc.py}
    python3 - <<'PY'
    import os
    import json
    from pathlib import Path
    import shlex
    import subprocess

    version = subprocess.check_output([shlex.split(os.environ["znc"])[0], "--version"], text=True)
    assert "Argon2: yes" in version

    template = Path(os.environ["template"]).read_text()
    assert template.count("@PASSWORD_HASH@") == 1
    assert template.count("@SAVEBUFF_KEY@") == 3
    assert "Host = 127.0.0.1" in template and "Port = 16667" in template
    assert "AllowWeb = false" in template and "SSL = false" in template
    assert "<User znc>" not in template
    assert "webadmin" not in template

    friend = Path(os.environ["friendTemplate"]).read_text()
    assert friend.count("@PASSWORD_HASH@") == 1
    assert friend.count("@SAVEBUFF_KEY@") == 2
    assert "<User friend>" in friend and "<User zairex>" not in friend
    plan_path = shlex.split(os.environ["friendPreStart"].strip().splitlines()[-1])[-1]
    plan = json.loads(Path(plan_path).read_text())
    assert plan == {
        "networkCount": 2,
        "sasl": [{
            "credential": "sasl-example.json",
            "target": "/var/lib/znc/users/friend/networks/example/moddata/sasl/.registry",
        }],
    }
    PY
    touch "$out"
  ''
