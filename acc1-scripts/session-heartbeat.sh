#!/bin/bash
# Session Heartbeat - Token-efficient context backup
# Saves ~150 tokens of structured context to Redis
# Runs via cron every 3 minutes

REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
SESSION_KEY="session:$TIMESTAMP"

# Find latest conversation
CONV_DIR="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects"
LATEST_CONV=$(ls -t "$CONV_DIR"/*.jsonl 2>/dev/null | head -1)

if [[ -z "$LATEST_CONV" ]]; then
    CONV_DIR="$HOME/.claude/projects/-root-claude-projects"
    LATEST_CONV=$(ls -t "$CONV_DIR"/*.jsonl 2>/dev/null | head -1)
fi

[[ -z "$LATEST_CONV" ]] && exit 0

# Extract compact context (~150 tokens)
SESSION_ID=$(basename "$LATEST_CONV" .jsonl)
MSG_COUNT=$(wc -l < "$LATEST_CONV")
FILE_SIZE=$(du -h "$LATEST_CONV" | cut -f1)

# Get last user message (what user asked)
LAST_USER=$(tail -100 "$LATEST_CONV" | grep '"role":"user"' | tail -1 | jq -r '.message.content // .display' 2>/dev/null | head -c 200)

# Get open issues (compact: just numbers)
OPEN_ISSUES=$(gh issue list --state open --limit 10 --repo arwoxbx24/claude-state --json number 2>/dev/null | jq -r '.[].number' | tr '\n' ',' | sed 's/,$//')

# Get current git branch and status
GIT_BRANCH=$(git -C /root/claude-projects branch --show-current 2>/dev/null)
GIT_STATUS=$(git -C /root/claude-projects status --porcelain 2>/dev/null | wc -l)

# Build compact summary (token-efficient)
COMPACT_SUMMARY="project:claude-projects|issues:${OPEN_ISSUES:-none}|msgs:$MSG_COUNT|branch:$GIT_BRANCH|uncommitted:$GIT_STATUS"

# Save to Redis (structured, minimal)
redis-cli -h $REDIS_HOST -p $REDIS_PORT HSET "$SESSION_KEY" \
    ts "$TIMESTAMP" \
    sid "$SESSION_ID" \
    msgs "$MSG_COUNT" \
    size "$FILE_SIZE" \
    issues "$OPEN_ISSUES" \
    branch "$GIT_BRANCH" \
    uncommitted "$GIT_STATUS" \
    last_ask "${LAST_USER:0:200}" \
    file "$LATEST_CONV" > /dev/null

# Update pointer + TTL
redis-cli -h $REDIS_HOST -p $REDIS_PORT SET "session:latest" "$SESSION_KEY" EX 604800 > /dev/null
redis-cli -h $REDIS_HOST -p $REDIS_PORT EXPIRE "$SESSION_KEY" 604800 > /dev/null

echo "[$(date)] Saved: $SESSION_KEY | $MSG_COUNT msgs | issues: $OPEN_ISSUES"
