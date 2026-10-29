{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.znc;
  renderer = "${./scripts/render_znc.py}";
  userName = builtins.head (builtins.attrNames cfg.config.User);
  configuredNetworks = cfg.config.User.${userName}.Network;
  saslNetworks = lib.filterAttrs (
    _: network: builtins.elem "sasl" (network.LoadModule or [ ])
  ) configuredNetworks;
  networkDirectory = name: "${cfg.dataDir}/users/${userName}/networks/${name}";
  runtimePlan = pkgs.writeText "znc-runtime.json" (
    builtins.toJSON {
      networkCount = builtins.length (builtins.attrNames configuredNetworks);
      sasl = lib.mapAttrsToList (name: _: {
        credential = "sasl-${name}.json";
        target = "${networkDirectory name}/moddata/sasl/.registry";
      }) saslNetworks;
    }
  );
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.length (builtins.attrNames cfg.config.User) == 1;
        message = "The runtime ZNC credential renderer supports exactly one login account.";
      }
    ];

    services.znc = {
      useLegacyConfig = false;
      mutable = false;
    };

    systemd.tmpfiles.rules = map (directory: "d ${directory} 0700 ${cfg.user} ${cfg.group} -") (
      [
        cfg.dataDir
        "${cfg.dataDir}/configs"
        "${cfg.dataDir}/users"
        "${cfg.dataDir}/users/${userName}"
        "${cfg.dataDir}/users/${userName}/networks"
      ]
      ++ lib.concatMap (name: [
        (networkDirectory name)
        "${networkDirectory name}/moddata"
        "${networkDirectory name}/moddata/sasl"
      ]) (builtins.attrNames saslNetworks)
    );

    systemd.services.znc = {
      preStart = lib.mkAfter ''
        ${pkgs.python3}/bin/python3 ${renderer} ${cfg.configFile} "$CREDENTIALS_DIRECTORY/znc.json" ${cfg.dataDir}/configs/znc.conf ${runtimePlan}
      '';
      serviceConfig.UMask = lib.mkForce "0077";
    };
  };
}
