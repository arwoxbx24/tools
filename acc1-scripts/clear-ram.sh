#!/usr/bin/env bash
set -euo pipefail

LOG=/var/log/clear-ram.log
THRESHOLD_MB=2048

ts="$(date '+%F %T')"
mem_avail_kb="$(awk '/MemAvailable/ {print $2}' /proc/meminfo)"

if (( mem_avail_kb > THRESHOLD_MB*1024 )); then
  echo "$ts Skip: MemAvailable=${mem_avail_kb}KB" >> "$LOG"
  exit 0
fi

echo "Start: $ts" >> "$LOG"
free -h >> "$LOG"
/bin/sync
/bin/echo 3 > /proc/sys/vm/drop_caches
echo "After:" >> "$LOG"
free -h >> "$LOG"
echo "----" >> "$LOG"
