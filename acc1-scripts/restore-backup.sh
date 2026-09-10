#!/bin/bash
# restore-backup.sh - Restore from encrypted Yandex.Disk backup
# Usage: ./restore-backup.sh [date] [file]
# Examples:
#   ./restore-backup.sh              # List current month backups
#   ./restore-backup.sh 2026-01      # List January 2026 backups
#   ./restore-backup.sh 2026-01 tokens.env.gpg  # Download and decrypt

set -euo pipefail

DATE="${1:-$(date +%Y-%m)}"
FILE="${2:-}"
PASSPHRASE_FILE="/root/workspaces/tools/acc1-scripts/config/.backup-passphrase"
RESTORE_DIR="/tmp/claude-restore-$$"
YANDEX_REMOTE="yandex:claude-backups"

if [[ ! -f "$PASSPHRASE_FILE" ]]; then
    echo "ERROR: Passphrase file not found: $PASSPHRASE_FILE"
    exit 1
fi

# List available backups
if [[ -z "$FILE" ]]; then
    echo "Available backups for $DATE:"
    echo "─────────────────────────────"
    rclone ls "$YANDEX_REMOTE/$DATE/" 2>/dev/null || echo "No backups found for $DATE"
    echo ""
    echo "Usage: $0 $DATE <filename.gpg>"
    exit 0
fi

mkdir -p "$RESTORE_DIR"

echo "Downloading $FILE..."
if ! rclone copy "$YANDEX_REMOTE/$DATE/$FILE" "$RESTORE_DIR/"; then
    echo "ERROR: Failed to download $FILE"
    rm -rf "$RESTORE_DIR"
    exit 1
fi

echo "Decrypting..."
OUTPUT_FILE="${FILE%.gpg}"
if gpg --batch --decrypt --passphrase-file "$PASSPHRASE_FILE" \
    -o "$RESTORE_DIR/$OUTPUT_FILE" "$RESTORE_DIR/$FILE" 2>/dev/null; then
    echo "✅ Restored to: $RESTORE_DIR/$OUTPUT_FILE"
    rm "$RESTORE_DIR/$FILE"
else
    echo "❌ Decryption failed"
    rm -rf "$RESTORE_DIR"
    exit 1
fi
