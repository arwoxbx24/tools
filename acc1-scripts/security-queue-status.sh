#!/bin/bash
# Security Queue Status
# Shows current queue size, today's stats, and processor status

REDIS_DB=5
TODAY=$(date +%Y-%m-%d)

echo "═══════════════════════════════════════════════════════════════"
echo " Security Queue Status — $(date '+%Y-%m-%d %H:%M:%S')"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Queue size
queue_size=$(redis-cli -n $REDIS_DB LLEN "security:queue" 2>/dev/null || echo "0")
echo "📋 Queue:           $queue_size files pending"

# Scanned today
scanned_today=$(redis-cli -n $REDIS_DB SCARD "security:scanned:$TODAY" 2>/dev/null || echo "0")
echo "✅ Scanned today:   $scanned_today files"

# Lock status
lock_pid=$(redis-cli -n $REDIS_DB GET "security:lock" 2>/dev/null)
if [[ -n "$lock_pid" ]]; then
    echo "🔒 Processor:       RUNNING (PID: $lock_pid)"
else
    echo "🔓 Processor:       idle"
fi

echo ""
echo "───────────────────────────────────────────────────────────────"
echo " Today's Statistics"
echo "───────────────────────────────────────────────────────────────"

# Get stats
files_scanned=$(redis-cli -n $REDIS_DB HGET "security:stats:$TODAY" "files_scanned" 2>/dev/null || echo "0")
issues_found=$(redis-cli -n $REDIS_DB HGET "security:stats:$TODAY" "issues_found" 2>/dev/null || echo "0")

echo "  Files scanned:    ${files_scanned:-0}"
echo "  Issues found:     ${issues_found:-0}"

echo ""
echo "───────────────────────────────────────────────────────────────"
echo " Recent Queue Entries (last 5)"
echo "───────────────────────────────────────────────────────────────"

entries=$(redis-cli -n $REDIS_DB LRANGE "security:queue" 0 4 2>/dev/null)
if [[ -n "$entries" ]]; then
    echo "$entries" | while read -r entry; do
        file=$(echo "$entry" | sed -n 's/.*"file":"\([^"]*\)".*/\1/p')
        project=$(echo "$entry" | sed -n 's/.*"project":"\([^"]*\)".*/\1/p')
        echo "  📁 $project: $(basename "$file")"
    done
else
    echo "  (empty)"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
echo "Commands:"
echo "  Clear queue:  redis-cli -n 5 DEL security:queue"
echo "  View logs:    tail -50 /root/workspaces/tools/acc1-scripts/pm2/logs/security-queue.log"
echo ""
