#!/usr/bin/env bash
# One-shot rollover to the simplified IRC setup (docs/miaucloud/IRC.md).
# Run once on miaucloud as root, from the updated /etc/nixos. Delete afterwards.
set -euo pipefail
umask 077

user=/var/data/znc/users/zairex

# Steps 1-3 are safe to rerun; step 4 recreates the znc user.
[ "$(id -u)" = 0 ] || { echo "Run as root." >&2; exit 1; }
[ "$(id -u znc)" = 1510820 ] || { echo "Unexpected znc uid $(id -u znc)." >&2; exit 1; }
[ -z "$(getent passwd 128)$(getent group 128)" ] || { echo "uid/gid 128 is taken." >&2; exit 1; }

echo "== 1/4 Building the new system (nothing changes yet)"
new=$(nix build --no-link --print-out-paths "/etc/nixos#nixosConfigurations.miaucloud-nixos.config.system.build.toplevel")
nix store diff-closures /run/current-system "$new"
read -r -p "Expect only IRC/backup changes above. Continue? [y/N] " answer
[ "$answer" = y ] || exit 1

echo "== 2/4 Generating the Libera client certificate"
cert=$(mktemp -d)
trap 'rm -rf -- "$cert"' EXIT
nix shell --inputs-from /etc/nixos nixpkgs-26-05#openssl -c \
  openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 -nodes -subj /CN=Zairex \
    -keyout "$cert/key.pem" -out "$cert/cert.pem"

echo "== 3/4 Stopping ZNC (all networks disconnect now) and moving data"
systemctl stop znc.service
# Playback is a cache encrypted with the retired key; the logs have everything.
rm -rf "$user"/networks/*/moddata/savebuff
if [ -d /home/zairex/.weechat/logs ] && [ ! -e /var/data/weechat-logs ]; then
  mv -T /home/zairex/.weechat/logs /var/data/weechat-logs
fi
mkdir -p "$user/moddata/cert"
cat "$cert/key.pem" "$cert/cert.pem" > "$user/moddata/cert/user.pem"
chown -hR 128:128 /var/data/znc

echo "== 4/4 Recreating user znc as 128:128, switching, starting ZNC"
# NixOS never changes the uid of an existing user; let activation recreate it.
userdel znc
if getent group znc > /dev/null; then groupdel znc; fi
switched=0
nixos-rebuild switch --flake /etc/nixos#miaucloud-nixos || switched=$?
systemctl start znc.service
[ "$switched" = 0 ] || { echo "The switch reported failures (see above); ZNC is started." >&2; exit 1; }

id znc
systemctl is-active znc.service znc-tailnet.service oidentd.service
echo "Done. Continue with step 3 in IRC.md."
