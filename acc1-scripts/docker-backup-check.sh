#!/usr/bin/env bash
set +e

# Docker Backup Check Script
# Verifies backup health and freshness

BACKUP_ROOT="/root/backups/docker"
ALERT_FILE="/root/workspaces/tools/acc1-scripts/data/backup-alert.txt"
MAX_AGE_HOURS=7

# Check if alert file exists (indicates backup failure)
if [ -f "$ALERT_FILE" ]; then
    echo "FAILED: Backup alert exists - $(cat "$ALERT_FILE")"
    exit 1
fi

# Find most recent backup directory
LATEST_BACKUP=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "20*" 2>/dev/null | sort -r | head -n1)

if [ -z "$LATEST_BACKUP" ]; then
    echo "FAILED: No backup directories found in $BACKUP_ROOT"
    exit 1
fi

# Check backup age
BACKUP_TIME=$(stat -c %Y "$LATEST_BACKUP" 2>/dev/null || stat -f %m "$LATEST_BACKUP" 2>/dev/null)
CURRENT_TIME=$(date +%s)
AGE_HOURS=$(( (CURRENT_TIME - BACKUP_TIME) / 3600 ))

if [ "$AGE_HOURS" -gt "$MAX_AGE_HOURS" ]; then
    echo "STALE: Last backup is ${AGE_HOURS}h old (max: ${MAX_AGE_HOURS}h) - $LATEST_BACKUP"
    exit 1
fi

# Check if backup has files and they're not empty
FILE_COUNT=$(find "$LATEST_BACKUP" -type f \( -name "*.sql.gz" -o -name "*.tar.gz" \) -size +100c 2>/dev/null | wc -l)

if [ "$FILE_COUNT" -lt 5 ]; then
    echo "INCOMPLETE: Only $FILE_COUNT valid backup files found in $LATEST_BACKUP (expected at least 5)"
    exit 1
fi

# All checks passed
BACKUP_NAME=$(basename "$LATEST_BACKUP")
echo "OK: Backup healthy - $BACKUP_NAME (${AGE_HOURS}h old, $FILE_COUNT files)"
exit 0
