# miaupi — Raspberry Pi home server

Configuration for `miaupi`, a Raspberry Pi 5 running the household's DNS, dashboards,
notes and git remotes. This repo is the **build index**: what differs from a fresh
Debian Pi and how to rebuild it. Working rule: change the live machine first, then
commit the change here.

## Base system

- Raspberry Pi 5 (8 GB), **Debian 12 (bookworm)**, aarch64 — the full Raspberry Pi OS
  desktop image. Hostname `miaupi`, timezone `Europe/Helsinki`.
- Root filesystem on the 64 GB SD card; external 1 TB HDD (`MiauExt`, ext4) for
  backups (see *Storage & data*).
- Everything below is what's added on top of that stock image.

## Services at a glance

| Service | Install | Runs as | Listens | Data | Upgrade |
|---|---|---|---|---|---|
| **Pi-hole** | upstream installer (not apt) | `pihole-FTL` systemd | 53 DNS, 8080/8443 admin | `/etc/pihole/` | `sudo pihole -up` |
| **Caddy** | apt (`caddy-stable.list`) | `caddy` systemd | 80, 443, 2019 (local admin) | `/etc/caddy/Caddyfile` → `caddy/` | `sudo apt upgrade caddy` |
| **Home Assistant** | Docker | container, host net | 8123 (+ dynamic integration ports) | `/opt/homeassistant/config/` | pull image, re-run start script |
| **Ollama** | Docker | container, host net | 11434 (LAN only) | `/opt/ollama/` | bump tag in start script, re-run |
| **Docker engine** | apt (`docker.list`) | `docker` systemd | — | `/var/lib/docker/` | apt |
| **Tailscale** | apt (`tailscale.list`) | `tailscaled` systemd | WireGuard (outbound) | `/var/lib/tailscale/` | apt |
| **ufw**, **smartmontools** | apt (Debian) | systemd | — | `/etc/ufw/` | apt |

Versions at last audit (2026-06-15): Pi-hole core v6.1.4 / FTL v6.2.3 (updates
available), Caddy 2.10.0, Docker 27.3.1, Tailscale 1.98.4, Home Assistant `stable`,
Ollama 0.12.6.

## Reverse proxy — `caddy/Caddyfile`

Installed at `/etc/caddy/Caddyfile`; the copy here is authoritative. Routes:
`pi.miau` and the Tailscale name → Home Assistant (`:8123`), with `/obsidian*` served
statically from `/srv/obsidian_notes`; `pi.hole` → Pi-hole admin (`:8080`).

## DNS — Pi-hole

The LAN's DNS resolver (the UniFi router hands this Pi out over DHCP). Installed with
the upstream Pi-hole installer and managed by the `pihole` CLI — **not an apt
package**. Config and the gravity DB live in `/etc/pihole/` (backed up nightly). Note:
while the Pi is down, LAN DNS is affected.

## Docker workloads

Two containers, both `--network=host` and `--restart=unless-stopped`, recreated from
the scripts here. State lives in the `/opt/...` bind-mount, so the container itself is
disposable (upgrade = pull/bump image, re-run the script):

- `homeassistant/start_homeassistant.sh` — HA; config in `/opt/homeassistant/config/`.
- `ollama/start_ollama.sh` — Ollama; models in `/opt/ollama/` (used by HA's hourly
  "story" sensor). *Planned: replace with llama.cpp.*

Docker engine itself is installed via `docker/install_docker.sh` (official repo). A
leftover dead `caddy` container from before native Caddy can be removed
(`docker rm caddy`).

## Scheduled jobs (root crontab)

```cron
0 2 * * *  .../device-configs/obsidian/sync_notes_to_serve.sh /home/zairex/git-repositories/TeeVault.git /srv/obsidian_notes
0 3 * * *  .../device-configs/backups/miaupi_backup.sh
```

- **02:00** — rebuild the Obsidian notes site (mkdocs) from `TeeVault.git` into
  `/srv/obsidian_notes`.
- **03:00** — `backups/miaupi_backup.sh` bundles git repos + `/etc/pihole/` + HA
  config into `/var/backups/miaupi_backup.tar.gz`.

## Storage & data

| What | Path |
|---|---|
| HA config / DB / `.storage` | `/opt/homeassistant/config/` |
| Ollama models | `/opt/ollama/` |
| Pi-hole config + gravity | `/etc/pihole/` |
| Git remotes (bare) | `/home/zairex/git-repositories/*.git` |
| Obsidian static site | `/srv/obsidian_notes/` |
| Nightly backup bundle | `/var/backups/miaupi_backup.tar.gz` |
| External backup drive | `/media/zairex/MiauExt/` (ext4) |

HDD mount in `/etc/fstab`:

```fstab
UUID=015d8adb-5058-4d4a-b32f-668f902331c7  /media/zairex/MiauExt  ext4  defaults,noatime,nofail  0  2
```

## Secrets (on the machine only — never committed here)

- Home Assistant: `/opt/homeassistant/config/secrets.yaml` + tokens under `.storage/`.
- Pi-hole admin password: `/etc/pihole/` (`cli_pw`).
- Tailscale node key: `/var/lib/tailscale/`.
- SSH: `~/.ssh/` (`authorized_keys`, `id_rsa`).

`.gitignore` only excludes the nix `result` symlink; no secret is tracked.

## Network in / out

- **Inbound** — ufw default `deny`; explicitly allowed: 22 (SSH), 80/443 (Caddy),
  53 tcp+udp (DNS), 8123 (HA direct). Everything else — including Ollama 11434 and
  Pi-hole admin 8080/8443 — is reachable only from LAN / localhost / Tailscale, not
  the open internet.
- **Tailscale** — joins tailnet `tail5b278e.ts.net` as `miaupi`; peers include
  `miaudesk` (the Windows backup source) and `miaucloud-nixos` (exit node).
- **Outbound** — apt mirrors, Docker/GHCR image pulls, Ollama model pulls, Tailscale
  coordination.

## Rebuild from scratch (outline)

1. Flash Raspberry Pi OS (Debian 12, 64-bit); set hostname `miaupi`, timezone, locale,
   SSH key.
2. `git clone` this repo to `~/Code/github/teekuningas/device-configs` (the cron lines
   assume that path).
3. Native installs: Pi-hole (upstream installer); `apt install` Caddy, Tailscale, ufw,
   smartmontools; Docker via `docker/install_docker.sh`.
4. Restore state from the latest `miaupi_backup.tar.gz`: `/etc/pihole/`, HA config,
   git repos; drop `caddy/Caddyfile` into `/etc/caddy/`.
5. Start the Docker workloads: `homeassistant/start_homeassistant.sh`,
   `ollama/start_ollama.sh`.
6. Firewall + VPN: ufw allow 22/80/443/53/8123 then enable; `tailscale up`.
7. Add the two root cron lines and the HDD fstab entry above; `sudo mount -a`.

## Possible improvements (not done yet)

- Make the imperative bits declarative — a `docker-compose.yml` for HA + Ollama, and
  the cron jobs as `/etc/cron.d/miaupi` or systemd timers — all living in this repo.
- Enable `unattended-upgrades` for apt security patches (not currently installed).
- Replace Ollama with llama.cpp; remove the empty `/opt/llamafile` and the dead
  `caddy` Docker container.
