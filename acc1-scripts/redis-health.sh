#!/bin/bash
# Redis Health Check
# Usage: ./redis-health.sh

echo "=== Redis Health Check ==="
echo ""

# Check if Redis is running
PING=$(redis-cli ping 2>/dev/null)
if [[ "$PING" == "PONG" ]]; then
    echo "Status: ✅ RUNNING"
else
    echo "Status: ❌ NOT RUNNING"
    exit 1
fi

# Memory info
MEM=$(redis-cli info memory | grep used_memory_human | cut -d: -f2 | tr -d '\r')
echo "Memory: $MEM"

# Keys count
KEYS=$(redis-cli DBSIZE | awk '{print $2}')
echo "Total keys: $KEYS"

# Session keys
SESSION_KEYS=$(redis-cli KEYS "session:*" | wc -l)
echo "Session keys: $SESSION_KEYS"

# Latest session
LATEST=$(redis-cli GET session:latest)
if [[ -n "$LATEST" ]]; then
    echo "Latest session: $LATEST"
    LAST_TS=$(redis-cli HGET "$LATEST" timestamp)
    echo "Last update: $LAST_TS"
else
    echo "Latest session: none"
fi

# Uptime
UPTIME=$(redis-cli info server | grep uptime_in_seconds | cut -d: -f2 | tr -d '\r')
UPTIME_H=$((UPTIME / 3600))
echo "Uptime: ${UPTIME_H}h"

echo ""
echo "=== Done ==="
