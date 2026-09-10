#!/bin/bash
# PM2 Scheduler: Clear RAM (every 30 minutes)
INTERVAL=1800  # 30 minutes

while true; do
    echo "[$(date -Iseconds)] Running clear-ram.sh"
    /root/workspaces/tools/acc1-scripts/scripts/clear-ram.sh 2>&1
    echo "[$(date -Iseconds)] Sleeping ${INTERVAL}s"
    sleep $INTERVAL
done
