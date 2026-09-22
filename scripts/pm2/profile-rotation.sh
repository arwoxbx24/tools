#!/bin/bash
set +e

# profile-rotation.sh — rotate and clean temp/cache data in Claude agent profile directory
# Schedule: PM2 cron, daily or weekly
# SCOPE: Only temp/cache dirs. NOT hooks/reference/rules-data/secrets/scripts/services/config/plans/mcp-servers
# NOTE: Logs, agent-reports, and context cleanup handled by file-cleanup-daemon.sh (PM2 #18)
# Удаление и обнуление переданы стадии уборки с гейтом restic (US3, spec:055); здесь осталась сводка размеров.

PROFILE_DIR="/root/workspaces/system/tools/scripts"
PM2_LOGS_DIR="/root/.pm2/logs"

echo "=== profile-rotation.sh START: $(date '+%Y-%m-%d %H:%M:%S') ==="
echo ""

# ─────────────────────────────────────────
# HELPER: print size of a path (if exists)
# ─────────────────────────────────────────
size_of() {
    local path="$1"
    if [ -e "$path" ]; then
        du -sh "$path" 2>/dev/null | awk '{print $1}'
    else
        echo "N/A"
    fi
}

# ─────────────────────────────────────────
# SUMMARY: Total profile dir size after cleanup
# ─────────────────────────────────────────
echo "--- SUMMARY ---"
echo "  Profile dir total size after cleanup: $(size_of "$PROFILE_DIR")"
echo "  PM2 logs dir size after cleanup:      $(size_of "$PM2_LOGS_DIR")"
echo ""
echo "=== profile-rotation.sh DONE: $(date '+%Y-%m-%d %H:%M:%S') ==="
