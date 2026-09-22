#!/bin/bash
set +e

# profile-rotation.sh — rotate and clean temp/cache data in Claude agent profile directory
# Schedule: PM2 cron, daily or weekly
# SCOPE: Only temp/cache dirs. NOT hooks/reference/rules-data/secrets/scripts/services/config/plans/mcp-servers
# NOTE: Logs, agent-reports, and context cleanup handled by file-cleanup-daemon.sh (PM2 #18)

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
# SECTION 1: Full cleanup directories
# (rm contents, keep dir structure)
# ─────────────────────────────────────────
FULL_CLEAN_DIRS=(
    "$PROFILE_DIR/debug"
    "$PROFILE_DIR/paste-cache"
    "$PROFILE_DIR/todos"
    "$PROFILE_DIR/tasks"
    "$PROFILE_DIR/session-env"
    "$PROFILE_DIR/shell-snapshots"
    "$PROFILE_DIR/telemetry"
    "$PROFILE_DIR/statsig"
)

echo "--- SECTION 1: Full directory cleanup ---"
for dir in "${FULL_CLEAN_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        before=$(size_of "$dir")
        find "$dir" -mindepth 1 -delete 2>/dev/null
        after=$(size_of "$dir")
        echo "  [CLEANED] $dir  before=$before  after=$after"
    else
        echo "  [SKIP] $dir (does not exist)"
    fi
done
echo ""

# ─────────────────────────────────────────
# SECTION 2: Age-based cleanup
# ─────────────────────────────────────────
echo "--- SECTION 2: Age-based cleanup ---"

# backups/ — older than 7 days
dir="$PROFILE_DIR/backups"
if [ -d "$dir" ]; then
    before=$(size_of "$dir")
    find "$dir" -mindepth 1 -mtime +7 -delete 2>/dev/null
    after=$(size_of "$dir")
    echo "  [AGE 7d] $dir  before=$before  after=$after"
else
    echo "  [SKIP] $dir (does not exist)"
fi

# file-history/ — older than 7 days
dir="$PROFILE_DIR/file-history"
if [ -d "$dir" ]; then
    before=$(size_of "$dir")
    find "$dir" -mindepth 1 -mtime +7 -delete 2>/dev/null
    after=$(size_of "$dir")
    echo "  [AGE 7d] $dir  before=$before  after=$after"
else
    echo "  [SKIP] $dir (does not exist)"
fi

# action-logs/ — older than 14 days
dir="$PROFILE_DIR/action-logs"
if [ -d "$dir" ]; then
    before=$(size_of "$dir")
    find "$dir" -mindepth 1 -mtime +14 -delete 2>/dev/null
    after=$(size_of "$dir")
    echo "  [AGE 14d] $dir  before=$before  after=$after"
else
    echo "  [SKIP] $dir (does not exist)"
fi

# data/session-restored-*.txt — delete all
dir="$PROFILE_DIR/data"
if [ -d "$dir" ]; then
    count=$(find "$dir" -maxdepth 1 -name "session-restored-*.txt" 2>/dev/null | wc -l)
    find "$dir" -maxdepth 1 -name "session-restored-*.txt" -delete 2>/dev/null
    echo "  [PATTERN] $dir/session-restored-*.txt  deleted=$count files"
else
    echo "  [SKIP] $dir (does not exist)"
fi

echo ""

# ─────────────────────────────────────────
# SECTION 3: Truncate large PM2 logs (>5MB)
# ─────────────────────────────────────────
echo "--- SECTION 3: PM2 log truncation (>5MB) ---"
if [ -d "$PM2_LOGS_DIR" ]; then
    truncated=0
    while IFS= read -r -d '' logfile; do
        before_size=$(du -sh "$logfile" 2>/dev/null | awk '{print $1}')
        : > "$logfile"
        echo "  [TRUNCATED] $logfile  was=$before_size"
        truncated=$((truncated + 1))
    done < <(find "$PM2_LOGS_DIR" -type f -size +5M -print0 2>/dev/null)
    if [ "$truncated" -eq 0 ]; then
        echo "  [OK] No PM2 logs exceed 5MB"
    fi
else
    echo "  [SKIP] $PM2_LOGS_DIR (does not exist)"
fi
echo ""

# ─────────────────────────────────────────
# SECTION 4: Clean /tmp/claude-* older than 1 day
# ─────────────────────────────────────────
echo "--- SECTION 4: /tmp/claude-* cleanup (>1 day) ---"
tmp_before=$(find /tmp -maxdepth 1 -name "claude-*" -mtime +1 2>/dev/null | wc -l)
find /tmp -maxdepth 1 -name "claude-*" -mtime +1 -exec rm -rf {} + 2>/dev/null
echo "  [CLEANED] /tmp/claude-*  deleted=$tmp_before items"
echo ""

# ─────────────────────────────────────────
# SECTION 5: Truncate advisory/compliance logs in /tmp
# ─────────────────────────────────────────
echo "--- SECTION 5: Truncate /tmp advisory logs ---"

for logfile in "/tmp/.hook-advisory.log" "/tmp/.compliance-pause.log"; do
    if [ -f "$logfile" ]; then
        before_size=$(du -sh "$logfile" 2>/dev/null | awk '{print $1}')
        : > "$logfile"
        echo "  [TRUNCATED] $logfile  was=$before_size"
    else
        echo "  [SKIP] $logfile (does not exist)"
    fi
done
echo ""

# ─────────────────────────────────────────
# SUMMARY: Total profile dir size after cleanup
# ─────────────────────────────────────────
echo "--- SUMMARY ---"
echo "  Profile dir total size after cleanup: $(size_of "$PROFILE_DIR")"
echo "  PM2 logs dir size after cleanup:      $(size_of "$PM2_LOGS_DIR")"
echo ""
echo "=== profile-rotation.sh DONE: $(date '+%Y-%m-%d %H:%M:%S') ==="
