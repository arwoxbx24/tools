#!/bin/bash
# ============================================================================
# Daemon: context-heartbeat-daemon.sh
# Purpose: Run context-heartbeat.sh every 30 seconds via PM2
# Protection Level: 3 (Tertiary - crash recovery)
# Bug #9 FIX: Log each cycle execution to daemon log
# ============================================================================

INTERVAL=30
SCRIPT="/root/workspaces/tools/acc1-scripts/schedulers/context-heartbeat.sh"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/context-heartbeat.log"

mkdir -p "$(dirname "$LOG_FILE")"

echo "[$(date '+%Y-%m-%d %H:%M:%S')] Context heartbeat daemon started (interval: ${INTERVAL}s)" | tee -a "$LOG_FILE"

while true; do
    # Bug #9 FIX: Log cycle start
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Heartbeat cycle running" >> "$LOG_FILE"
    "$SCRIPT" >> "$LOG_FILE" 2>&1 || true
    sleep $INTERVAL
done
