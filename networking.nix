{ lib, ... }: {
  # This file was populated at runtime with the networking
  # details gathered from the active system.
  networking = {
    nameservers = [ "8.8.8.8"
 ];
    defaultGateway = "64.226.96.1";
    defaultGateway6 = {
      address = "";
      interface = "eth0";
    };
    dhcpcd.enable = false;
    usePredictableInterfaceNames = lib.mkForce false;
    interfaces = {
      eth0 = {
        ipv4.addresses = [
          { address="64.226.104.65"; prefixLength=20; }
{ address="10.19.0.5"; prefixLength=16; }
        ];
        ipv6.addresses = [
          { address="fe80::b4e0:4aff:fef2:7d6e"; prefixLength=64; }
        ];
        ipv4.routes = [ { address = "64.226.96.1"; prefixLength = 32; } ];
        ipv6.routes = [ { address = ""; prefixLength = 128; } ];
      };
      
    };
  };
  services.udev.extraRules = ''
    ATTR{address}=="b6:e0:4a:f2:7d:6e", NAME="eth0"
    ATTR{address}=="d6:91:04:63:20:a3", NAME="eth1"
  '';
}
