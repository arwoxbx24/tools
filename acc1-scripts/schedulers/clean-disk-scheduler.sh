#!/bin/bash
# PM2 Scheduler: Clean Disk (daily at 3:00 AM)
TARGET_HOUR=3
TARGET_MIN=0

while true; do
    current_hour=$(date +%H)
    current_min=$(date +%M)
    
    # Calculate seconds until target time
    now_sec=$((10#$current_hour * 3600 + 10#$current_min * 60))
    target_sec=$((TARGET_HOUR * 3600 + TARGET_MIN * 60))
    
    if [ $now_sec -ge $target_sec ]; then
        # Already past target, schedule for tomorrow
        sleep_sec=$((86400 - now_sec + target_sec))
    else
        sleep_sec=$((target_sec - now_sec))
    fi
    
    echo "[$(date -Iseconds)] Next run in ${sleep_sec}s (at 03:00)"
    sleep $sleep_sec
    
    echo "[$(date -Iseconds)] Running clean-disk.sh"
    /root/workspaces/tools/acc1-scripts/scripts/clean-disk.sh 2>&1
    
    # Sleep 1 minute to avoid double run
    sleep 60
done
