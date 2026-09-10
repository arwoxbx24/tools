#!/bin/bash
# load-session.sh <project> [key]
# Loads from Redis first, falls back to file
PROJECT="${1:?Usage: load-session.sh <project> [key]}"
KEY="$2"

if [ -n "$KEY" ]; then
    # Get specific key
    VAL=$(redis-cli HGET "session:${PROJECT}:latest" "$KEY" 2>/dev/null)
    if [ -n "$VAL" ] && [ "$VAL" != "(nil)" ]; then
        echo "$VAL"
    else
        # Fallback: search session files
        SESSION_DIR="/root/workspaces/tools/acc1-scripts/sessions"
        grep -h "\"project\":\"$PROJECT\"" "${SESSION_DIR}"/*/"${PROJECT}.jsonl" 2>/dev/null | grep "\"key\":\"$KEY\"" | tail -1
    fi
else
    # Get all keys for project
    redis-cli HGETALL "session:${PROJECT}:latest" 2>/dev/null
fi
