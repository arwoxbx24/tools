#!/bin/bash
# encrypted-backup.sh - Encrypted backup to Yandex.Disk
# Usage: ./encrypted-backup.sh [--full]
# Cron: 0 4 * * * /root/workspaces/tools/acc1-scripts/scripts/encrypted-backup.sh

set -euo pipefail

BACKUP_DIR="/tmp/claude-backup-$(date +%Y%m%d-%H%M)"
YANDEX_REMOTE="yandex:claude-backups"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/backup.log"
PASSPHRASE_FILE="/root/workspaces/tools/acc1-scripts/config/.backup-passphrase"

SECRETS_FILES=(
    "/root/.claude_shared/config/tokens.env"
    "/root/workspaces/tools/acc1-scripts/.credentials.json"
)
LARGE_FILES=(
    "/root/workspaces/tools/acc1-scripts/data/vectors.db"
)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"; }

mkdir -p "$(dirname "$LOG_FILE")"

if [[ ! -f "$PASSPHRASE_FILE" ]]; then
    log "ERROR: Passphrase file not found: $PASSPHRASE_FILE"
    exit 1
fi

mkdir -p "$BACKUP_DIR"

log "=== Backup started ==="

# Encrypt secrets (daily)
log "Encrypting secrets..."
for file in "${SECRETS_FILES[@]}"; do
    if [[ -f "$file" ]]; then
        name=$(basename "$file")
        gpg --batch --yes --symmetric --cipher-algo AES256 \
            --passphrase-file "$PASSPHRASE_FILE" \
            -o "$BACKUP_DIR/${name}.gpg" "$file" 2>/dev/null
        log "  ✓ $name"
    else
        log "  ⚠ $file not found, skipping"
    fi
done

# Encrypt large files (weekly or --full)
if [[ "${1:-}" == "--full" ]] || [[ $(date +%u) -eq 7 ]]; then
    log "Encrypting large files..."
    for file in "${LARGE_FILES[@]}"; do
        if [[ -f "$file" ]]; then
            name=$(basename "$file")
            gpg --batch --yes --symmetric --cipher-algo AES256 \
                --passphrase-file "$PASSPHRASE_FILE" \
                -o "$BACKUP_DIR/${name}.gpg" "$file" 2>/dev/null
            log "  ✓ $name ($(du -h "$file" | cut -f1))"
        else
            log "  ⚠ $file not found, skipping"
        fi
    done
fi

# Check if rclone yandex remote exists
if ! rclone listremotes 2>/dev/null | grep -q "yandex:"; then
    log "ERROR: Yandex remote not configured. Run: rclone config"
    rm -rf "$BACKUP_DIR"
    exit 1
fi

# Upload
log "Uploading to Yandex.Disk..."
if rclone copy "$BACKUP_DIR" "$YANDEX_REMOTE/$(date +%Y-%m)/" 2>&1 | tee -a "$LOG_FILE"; then
    log "✅ Backup complete: $(ls -1 "$BACKUP_DIR" | wc -l) files uploaded"
else
    log "❌ Upload failed"
    rm -rf "$BACKUP_DIR"
    exit 1
fi

rm -rf "$BACKUP_DIR"
log "=== Backup finished ==="
