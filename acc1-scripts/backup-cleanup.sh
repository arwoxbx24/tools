#!/bin/bash
# Backup cleanup script
# Moves .claude.json.backup.* to backups/ folder
# Deletes backups older than 5 days

PROFILE_DIR="/root/workspaces/tools/acc1-scripts"
BACKUP_DIR="${PROFILE_DIR}/backups"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Move existing backups from root to backups/
moved=0
for f in "$PROFILE_DIR"/.claude.json.backup.*; do
    [ -f "$f" ] || continue
    mv "$f" "$BACKUP_DIR/" 2>/dev/null && ((moved++))
done

# Delete backups older than 5 days
deleted=$(find "$BACKUP_DIR" -name "*.backup.*" -mtime +5 -delete -print 2>/dev/null | wc -l)

# Report
if [ "$moved" -gt 0 ] || [ "$deleted" -gt 0 ]; then
    echo "Backup cleanup: moved=$moved, deleted=$deleted"
fi
