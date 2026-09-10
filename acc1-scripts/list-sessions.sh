#!/bin/bash
# list-sessions.sh [project] [--days N]
PROJECT="$1"
DAYS="${2:-5}"

echo "=== Redis sessions ==="
if [ -n "$PROJECT" ]; then
    redis-cli KEYS "session:${PROJECT}:*" 2>/dev/null
else
    redis-cli KEYS "session:*" 2>/dev/null | sort | head -50
fi

echo ""
echo "=== File sessions (last ${DAYS} days) ==="
find /root/workspaces/tools/acc1-scripts/sessions/ -name "*.jsonl" -mtime -${DAYS} 2>/dev/null | sort
