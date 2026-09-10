#!/bin/bash
# Unified Scheduler Daemon (replaces crontab)
# Manages all periodic tasks for claude_expert profile
#
# Tasks:
# - Every 3 min: heartbeat
# - Every 10 min: sync rules, cleanup tmp
# - Every 15 min: auto push
# - Every 18 hours: git optimize
# - Daily at 4:00: backup, db optimize
# - 1st and 15th: git squash

set -euo pipefail

CONFIG_DIR="/root/workspaces/tools/acc1-scripts"
SCRIPTS_DIR="$CONFIG_DIR/scripts"
LOG_FILE="$CONFIG_DIR/logs/scheduler.log"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

log "Scheduler daemon started"

# Counters (in minutes)
COUNTER=0
LAST_OPTIMIZE_HOUR=0
LAST_DAILY_DAY=0

while true; do
    CURRENT_HOUR=$(date +%H)
    CURRENT_DAY=$(date +%d)
    CURRENT_MIN=$(date +%M)

    # Every 3 minutes: heartbeat
    if (( COUNTER % 3 == 0 )); then
        [ -x "$SCRIPTS_DIR/heartbeat.sh" ] && "$SCRIPTS_DIR/heartbeat.sh" >> "$LOG_FILE" 2>&1 || true
    fi

    # Every 10 minutes: sync rules, cleanup tmp
    if (( COUNTER % 10 == 0 )); then
        [ -x "$SCRIPTS_DIR/sync-rules.sh" ] && "$SCRIPTS_DIR/sync-rules.sh" >> "$LOG_FILE" 2>&1 || true
        [ -x "$SCRIPTS_DIR/cleanup-tmp.sh" ] && "$SCRIPTS_DIR/cleanup-tmp.sh" >> "$LOG_FILE" 2>&1 || true
    fi

    # Every 15 minutes: auto push
    if (( COUNTER % 15 == 0 )); then
        [ -x "$SCRIPTS_DIR/auto-push.sh" ] && "$SCRIPTS_DIR/auto-push.sh" >> "$LOG_FILE" 2>&1 || true
    fi

    # Every 18 hours: git optimize (check by hour)
    HOURS_SINCE_START=$((COUNTER / 60))
    if (( HOURS_SINCE_START > 0 && HOURS_SINCE_START % 18 == 0 && HOURS_SINCE_START != LAST_OPTIMIZE_HOUR )); then
        LAST_OPTIMIZE_HOUR=$HOURS_SINCE_START
        [ -x "$SCRIPTS_DIR/git-optimize.sh" ] && "$SCRIPTS_DIR/git-optimize.sh" >> "$LOG_FILE" 2>&1 || true
        log "Git optimize completed"
    fi

    # Daily at 4:00: backup, db optimize
    if [[ "$CURRENT_HOUR" == "04" && "$CURRENT_MIN" == "00" && "$CURRENT_DAY" != "$LAST_DAILY_DAY" ]]; then
        LAST_DAILY_DAY=$CURRENT_DAY
        [ -x "$SCRIPTS_DIR/backup-cleanup.sh" ] && "$SCRIPTS_DIR/backup-cleanup.sh" >> "$LOG_FILE" 2>&1 || true
        log "Daily backup completed"
    fi

    # 1st and 15th of month: git squash
    if [[ ("$CURRENT_DAY" == "01" || "$CURRENT_DAY" == "15") && "$CURRENT_HOUR" == "05" && "$CURRENT_MIN" == "00" ]]; then
        [ -x "$SCRIPTS_DIR/git-squash-old.sh" ] && "$SCRIPTS_DIR/git-squash-old.sh" >> "$LOG_FILE" 2>&1 || true
        log "Git squash completed"
    fi

    COUNTER=$((COUNTER + 1))
    # Reset counter to prevent overflow
    if (( COUNTER > 43200 )); then  # 30 days in minutes
        COUNTER=0
    fi

    sleep 60
done
