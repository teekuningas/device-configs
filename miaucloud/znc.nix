# The IRC bouncer itself: plain NixOS `services.znc`, nothing else.
# How miaucloud runs and exposes it lives in znc-host.nix.
{ lib, pkgs, ... }:
let
  # Per-device playback, playback that survives restarts, permanent logs.
  modules = [ "clientbuffer autoadd" "savebuff" "log" ];
in
{
  services.znc = {
    enable = true;
    mutable = false; # znc.conf is regenerated from this file on every start
    useLegacyConfig = false;
    modulePackages = [ pkgs.zncModules.clientbuffer ];

    config.User.zairex = {
      Nick = "Zairex";
      AltNick = "Zairex_";
      Ident = "zairex";
      RealName = "Zairex";
      MaxNetworks = 3;
      ChanBufferSize = 500;
      QueryBufferSize = 500;
      AutoClearChanBuffer = false;
      AutoClearQueryBuffer = false;

      # From `znc --makepass`: Argon2id of a 256-bit random password, safe to publish.
      Pass.password = {
        Method = "Argon2id";
        Hash = "$argon2id$v=19$m=6144,t=6,p=1$K2t5R0JLKlcoSldwKS42cUppckI$NhhCRM7PR94eFok9+GGJ8IalyivQe7yerqlo2Ndkc+I";
      };

      # Client certificate in users/zairex/moddata/cert/user.pem (Libera SASL EXTERNAL).
      LoadModule = [ "cert" ];

      Network = {
        libera = {
          Server = [ "irc.libera.chat +6697" ];
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
    };
  };
}
