set -euo pipefail
IFS=$'\n\t'
umask 0077

### Configuration ###
POSTGRES_CONTAINER_NAME="postgres"
POSTGRES_PGUSER="postgres"
POSTGRES_BACKUP_DIR="/var/backups/all_data/postgres"
POSTGRES_FINAL_NAME="pg_dumpall.sql.gz"
POSTGRES_TMP_FILE="$POSTGRES_BACKUP_DIR/${POSTGRES_FINAL_NAME}.tmp"
POSTGRES_FINAL_FILE="$POSTGRES_BACKUP_DIR/$POSTGRES_FINAL_NAME"

BACKUP_DIR="/var/backups/all_data"
DATA_ROOT="/var/data"
# list the sub‐folders you want to back up
DATA_DIRS=(
  kingofsweden
  meggie
  .secrets
  static
  vellubot
  znc
)
FINAL_ARCHIVE="/var/backups/data_backup.tar.gz"
######################

echo "[INFO] $(date '+%F %T') Starting full backup"

# 1) prepare a clean backup directory
echo "[INFO] Cleaning and recreating $BACKUP_DIR"
rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

# 2) backup Postgres (into $BACKUP_DIR/postgres)
echo "[INFO] Backing up Postgres"

# Clean up temporary files on exit/failure
trap 'rm -f -- "$POSTGRES_TMP_FILE" "$FINAL_ARCHIVE.tmp"' EXIT

# Ensure the backup directory exists
mkdir -p "$POSTGRES_BACKUP_DIR"

echo "[ $(date '+%F %T') ] Starting Postgres full dump from container '$POSTGRES_CONTAINER_NAME'..."

# Run pg_dumpall in the container, compress into a temp file
podman exec -i "$POSTGRES_CONTAINER_NAME" \
    pg_dumpall -U "$POSTGRES_PGUSER" \
  | gzip > "$POSTGRES_TMP_FILE"

# Atomically move the temp file into place, overwriting any previous dump
mv -f "$POSTGRES_TMP_FILE" "$POSTGRES_FINAL_FILE"

# Ensure data is on disk
sync

echo "[ $(date '+%F %T') ] Backup complete → $POSTGRES_FINAL_FILE"

# 3) rsync each of the listed data folders
echo "[INFO] Rsync’ing /var/data subdirectories"
for d in "${DATA_DIRS[@]}"; do
  SRC="$DATA_ROOT/$d"
  DST="$BACKUP_DIR/$d"
  if [[ -e "$SRC" ]]; then
    echo "[INFO]   → $SRC → $DST"
    mkdir -p "$DST"
    rsync -a --delete "$SRC/" "$DST/"
  else
    echo "[WARN]   → source $SRC not found, skipping"
  fi
done

rsync -a --delete /home/zairex/.weechat/ "$BACKUP_DIR/weechat/"
rsync -a --delete /home/zairex/.config/znc/ "$BACKUP_DIR/znc-client/"

# 4) replace the single archive only after the new copy is complete
echo "[INFO] Creating $FINAL_ARCHIVE"
rm -f -- "$FINAL_ARCHIVE.tmp"
tar -C "$BACKUP_DIR" -czf "$FINAL_ARCHIVE.tmp" .
mv -f "$FINAL_ARCHIVE.tmp" "$FINAL_ARCHIVE"

echo "[INFO] $(date '+%F %T') Backup complete: $FINAL_ARCHIVE"
exit 0
