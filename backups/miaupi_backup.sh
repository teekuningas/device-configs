#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

### Configuration ###
BACKUP_DIR="/var/backups/miaupi_backup"
FINAL_ARCHIVE="/var/backups/miaupi_backup.tar.gz"
USER_HOME="/home/zairex"
######################

echo "[INFO] $(date '+%F %T') Starting miaupi backup"

# 1) Prepare a clean backup directory
echo "[INFO] Cleaning and recreating $BACKUP_DIR"
sudo rm -rf "$BACKUP_DIR"
sudo mkdir -p "$BACKUP_DIR"

# 2) Backup git repositories
echo "[INFO] Backing up git repositories"
GIT_BACKUP_DIR="$BACKUP_DIR/git-repositories"
sudo mkdir -p "$GIT_BACKUP_DIR"
sudo rsync -a --delete "$USER_HOME/git-repositories/" "$GIT_BACKUP_DIR/"

# 3) Backup Pi-hole config
echo "[INFO] Backing up Pi-hole config"
PIHOLE_BACKUP_DIR="$BACKUP_DIR/pihole"
sudo mkdir -p "$PIHOLE_BACKUP_DIR"
sudo rsync -a --delete /etc/pihole/ "$PIHOLE_BACKUP_DIR/"

# 4) Backup Home Assistant data
echo "[INFO] Backing up Home Assistant config"
HA_BACKUP_DIR="$BACKUP_DIR/homeassistant"
sudo mkdir -p "$HA_BACKUP_DIR"
sudo rsync -a --delete /opt/homeassistant/config/ "$HA_BACKUP_DIR/"

# 5) Create the final tar.gz archive (overwriting any existing one)
echo "[INFO] Creating $FINAL_ARCHIVE"
sudo tar -C "$BACKUP_DIR" -czf "$FINAL_ARCHIVE" .

# 6) Make the archive readable by the user for SCP transfer
sudo chmod 644 "$FINAL_ARCHIVE"

echo "[INFO] $(date '+%F %T') Backup complete: $FINAL_ARCHIVE"
echo "[INFO] Archive size: $(du -h $FINAL_ARCHIVE | cut -f1)"

exit 0
