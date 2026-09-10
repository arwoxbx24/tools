#!/bin/bash
# Cleanup public/tmp - files older than 10 days
TMP_DIR="/root/claude-projects/bitrix-migration-sdkphp/public/tmp"
if [ -d "$TMP_DIR" ]; then
    COUNT=$(find "$TMP_DIR" -type f -mtime +10 | wc -l)
    find "$TMP_DIR" -type f -mtime +10 -delete
    echo "$(date): Deleted $COUNT files older than 10 days from $TMP_DIR"
fi
