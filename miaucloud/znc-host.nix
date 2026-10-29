# How miaucloud runs the bouncer from znc.nix. None of this is needed by ZNC
# itself: on its own, znc.nix listens with TLS on port 5000.
{ config, lib, pkgs, unstable-pkgs, ... }:
let
  port = 16667;
in
{
  # Package: stable ZNC (1.10.1) is built without Argon2, which our hash needs.
  # Drop this overlay once stable ships ZNC >= 1.10.3 with Argon2 enabled.
  nixpkgs.overlays = [
    (_: _: {
      znc = unstable-pkgs.znc.overrideAttrs (old: {
        buildInputs = old.buildInputs ++ [ unstable-pkgs.libargon2 ];
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DWANT_ARGON=YES" ];
      });
    })
  ];

  # State: under /var/data, which data-backup archives.
  services.znc.dataDir = "/var/data/znc";

  # Operation: a restart drops every upstream connection, so only restart
  # deliberately; logs are private to the service.
  systemd.services.znc = {
    restartIfChanged = false;
    serviceConfig.UMask = lib.mkForce "0077";
  };

  # Access: plaintext on loopback only; Tailscale terminates TLS for tailnet
  # devices at miaucloud-nixos.tail5b278e.ts.net:6697.
  services.znc.config.Listener.l = {
    Host = "127.0.0.1";
    Port = port;
    IPv6 = false;
    SSL = false;
    AllowWeb = false;
  };
  systemd.services.znc-tailnet = {
    description = "Tailnet-only TLS ingress for ZNC";
    wantedBy = [ "multi-user.target" ];
    wants = [ "tailscaled.service" ];
    after = [ "tailscaled.service" ];
    serviceConfig = {
      ExecStart = "${lib.getExe config.services.tailscale.package} serve --tls-terminated-tcp=6697 tcp://127.0.0.1:${toString port}";
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

  # Ident: upstream servers see `zairex` instead of `~znc`. The stock oidentd
  # unit has no config option, hence the script override.
  services.oidentd.enable = true;
  systemd.services.oidentd.script = lib.mkForce ''
    ${pkgs.oidentd}/sbin/oidentd -u oidentd -g nogroup -C ${pkgs.writeText "oidentd.conf" ''
      user "znc" {
        default {
          force reply "${config.services.znc.config.User.zairex.Ident}"
        }
      }
    ''}
  '';
  networking.firewall.allowedTCPPorts = [ 113 ];
}
