#!/bin/bash
# save-session.sh <project> <key> <value> [ttl_seconds]
# Saves data to Redis with 5-day TTL, logs to session file
PROJECT="${1:?Usage: save-session.sh <project> <key> <value>}"
KEY="${2:?}"
VALUE="${3:?}"
TTL="${4:-432000}"  # 5 days default

# Layer 1: Redis
redis-cli HSET "session:${PROJECT}:latest" "$KEY" "$VALUE" 2>/dev/null
redis-cli EXPIRE "session:${PROJECT}:latest" "$TTL" 2>/dev/null

# Layer 2: File (auto-committed by auto-commit daemon)
SESSION_DIR="/root/workspaces/tools/acc1-scripts/sessions/$(date +%Y-%m-%d)"
mkdir -p "$SESSION_DIR"
echo "{\"project\":\"$PROJECT\",\"key\":\"$KEY\",\"value\":\"$VALUE\",\"timestamp\":\"$(date -Iseconds)\"}" >> "${SESSION_DIR}/${PROJECT}.jsonl"

echo "OK: saved ${PROJECT}:${KEY}"
