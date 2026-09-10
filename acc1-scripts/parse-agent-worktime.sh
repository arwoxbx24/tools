#!/bin/bash

# parse-agent-worktime.sh
# Parse agent JSONL files and extract work time duration
# Stores results in Redis DB 6

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check dependencies
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is not installed${NC}"
    exit 1
fi

if ! command -v redis-cli &> /dev/null; then
    echo -e "${RED}Error: redis-cli is not installed${NC}"
    exit 1
fi

# Usage
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <agent-jsonl-file>"
    echo ""
    echo "Example:"
    echo "  $0 /tmp/claude-session/agents/a87a701.jsonl"
    exit 1
fi

JSONL_FILE="$1"

# Check file exists
if [[ ! -f "$JSONL_FILE" ]]; then
    echo -e "${RED}Error: File not found: $JSONL_FILE${NC}"
    exit 1
fi

# Check file is not empty
if [[ ! -s "$JSONL_FILE" ]]; then
    echo -e "${RED}Error: File is empty: $JSONL_FILE${NC}"
    exit 1
fi

# Extract agent ID from filename (e.g., a87a701.jsonl -> a87a701)
AGENT_ID=$(basename "$JSONL_FILE" .jsonl)

# Count total messages (lines)
MSG_COUNT=$(wc -l < "$JSONL_FILE")

# Handle single message case
if [[ $MSG_COUNT -eq 1 ]]; then
    echo -e "${YELLOW}Warning: Only 1 message in file. Duration will be 0.${NC}"
fi

# Extract first and last timestamps
FIRST_TS=$(head -n 1 "$JSONL_FILE" | jq -r '.timestamp // empty')
LAST_TS=$(tail -n 1 "$JSONL_FILE" | jq -r '.timestamp // empty')

# Validate timestamps
if [[ -z "$FIRST_TS" || "$FIRST_TS" == "null" ]]; then
    echo -e "${RED}Error: Could not extract first timestamp${NC}"
    exit 1
fi

if [[ -z "$LAST_TS" || "$LAST_TS" == "null" ]]; then
    echo -e "${RED}Error: Could not extract last timestamp${NC}"
    exit 1
fi

# Convert ISO 8601 timestamps to Unix seconds
START_SEC=$(date -d "$FIRST_TS" +%s 2>/dev/null || echo "")
END_SEC=$(date -d "$LAST_TS" +%s 2>/dev/null || echo "")

# Validate conversions
if [[ -z "$START_SEC" || -z "$END_SEC" ]]; then
    echo -e "${RED}Error: Invalid timestamp format${NC}"
    echo "First: $FIRST_TS"
    echo "Last: $LAST_TS"
    exit 1
fi

# Calculate duration
DURATION=$((END_SEC - START_SEC))

# Extract model from message content
# Try to find model in any message
MODEL=$(jq -r '
    select(.role == "user" or .role == "assistant") |
    .content // "" |
    if type == "array" then
        .[] | select(.type == "text") | .text
    else
        .
    end' "$JSONL_FILE" | grep -oP '(opus|sonnet|haiku|claude-[a-z0-9-]+)' | head -n 1 || echo "unknown")

# If model detection fails, try alternative methods
if [[ "$MODEL" == "unknown" || -z "$MODEL" ]]; then
    # Try to extract from metadata or config
    MODEL=$(jq -r '.model // .metadata.model // empty' "$JSONL_FILE" | head -n 1 || echo "unknown")
fi

# Fallback to detecting from agent ID pattern or filename
if [[ "$MODEL" == "unknown" || -z "$MODEL" ]]; then
    # Common patterns: opus-, sonnet-, haiku-
    if echo "$AGENT_ID" | grep -qE '^(opus|sonnet|haiku)'; then
        MODEL=$(echo "$AGENT_ID" | grep -oE '^(opus|sonnet|haiku)')
    else
        MODEL="unknown"
    fi
fi

# Format duration nicely
format_duration() {
    local total_sec=$1
    local hours=$((total_sec / 3600))
    local minutes=$(((total_sec % 3600) / 60))
    local seconds=$((total_sec % 60))

    if [[ $total_sec -lt 60 ]]; then
        echo "${seconds}s"
    elif [[ $total_sec -lt 3600 ]]; then
        echo "${minutes}m ${seconds}s"
    else
        echo "${hours}h ${minutes}m ${seconds}s"
    fi
}

DURATION_FORMATTED=$(format_duration "$DURATION")

# Get date for Redis keys (YYYY-MM-DD)
DATE=$(date -d "@$START_SEC" +%Y-%m-%d)

# Store in Redis DB 6
redis-cli -n 6 HSET "worktime:agent:$AGENT_ID:$DATE" \
    start_ts "$START_SEC" \
    end_ts "$END_SEC" \
    duration_sec "$DURATION" \
    message_count "$MSG_COUNT" \
    model "$MODEL" \
    status "completed" \
    file_path "$JSONL_FILE" \
    >/dev/null

# Set expiration (30 days)
redis-cli -n 6 EXPIRE "worktime:agent:$AGENT_ID:$DATE" 2592000 >/dev/null

# Update daily totals
redis-cli -n 6 HINCRBY "worktime:daily:$DATE" total_duration_sec "$DURATION" >/dev/null
redis-cli -n 6 HINCRBY "worktime:daily:$DATE" total_agents 1 >/dev/null
redis-cli -n 6 EXPIRE "worktime:daily:$DATE" 2592000 >/dev/null

# Update model totals
if [[ "$MODEL" != "unknown" ]]; then
    redis-cli -n 6 HINCRBY "worktime:model:$MODEL:$DATE" total_seconds "$DURATION" >/dev/null
    redis-cli -n 6 HINCRBY "worktime:model:$MODEL:$DATE" agent_count 1 >/dev/null
    redis-cli -n 6 EXPIRE "worktime:model:$MODEL:$DATE" 2592000 >/dev/null
fi

# Format start and end times for display
START_TIME=$(date -d "@$START_SEC" '+%Y-%m-%d %H:%M:%S')
END_TIME=$(date -d "@$END_SEC" '+%Y-%m-%d %H:%M:%S')

# Output
echo -e "${BLUE}⏱️  Agent Work Time: ${AGENT_ID}${NC}"
echo "─────────────────────────────────"
echo -e "${GREEN}Model:${NC}        $MODEL"
echo -e "${GREEN}Start:${NC}        $START_TIME"
echo -e "${GREEN}End:${NC}          $END_TIME"
echo -e "${GREEN}Duration:${NC}     $DURATION_FORMATTED"
echo -e "${GREEN}Messages:${NC}     $MSG_COUNT"
echo "─────────────────────────────────"
echo -e "${BLUE}Saved to Redis DB 6${NC}"

# Optional: Show daily summary
DAILY_TOTAL=$(redis-cli -n 6 HGET "worktime:daily:$DATE" total_duration_sec 2>/dev/null || echo "0")
DAILY_AGENTS=$(redis-cli -n 6 HGET "worktime:daily:$DATE" total_agents 2>/dev/null || echo "0")

if [[ "$DAILY_TOTAL" != "0" && "$DAILY_AGENTS" != "0" ]]; then
    DAILY_FORMATTED=$(format_duration "$DAILY_TOTAL")
    echo ""
    echo -e "${YELLOW}📊 Daily Total ($DATE):${NC}"
    echo "   Agents: $DAILY_AGENTS"
    echo "   Total Time: $DAILY_FORMATTED"
fi

exit 0

# USAGE EXAMPLES:
#
# Parse single agent file:
#   parse-agent-worktime.sh /tmp/claude-session/agents/a87a701.jsonl
#
# Parse all agent files in directory:
#   for file in /tmp/claude-session/agents/*.jsonl; do
#     parse-agent-worktime.sh "$file"
#   done
#
# REDIS KEYS STRUCTURE:
#
# Agent-specific:
#   worktime:agent:<agent_id>:<date>
#     - start_ts: Unix timestamp (seconds)
#     - end_ts: Unix timestamp (seconds)
#     - duration_sec: Total duration in seconds
#     - message_count: Number of messages
#     - model: Model name (opus/sonnet/haiku/unknown)
#     - status: "completed"
#     - file_path: Original JSONL file path
#
# Daily aggregates:
#   worktime:daily:<date>
#     - total_duration_sec: Sum of all agent durations
#     - total_agents: Count of agents
#
# Model aggregates:
#   worktime:model:<model>:<date>
#     - total_seconds: Sum of durations for this model
#     - agent_count: Number of agents using this model
#
# All keys expire after 30 days (2592000 seconds)
#
# QUERY EXAMPLES:
#
# Get all agents for specific date:
#   redis-cli -n 6 KEYS "worktime:agent:*:2026-02-02"
#
# Get daily summary:
#   redis-cli -n 6 HGETALL "worktime:daily:2026-02-02"
#
# Get model statistics:
#   redis-cli -n 6 HGETALL "worktime:model:sonnet:2026-02-02"
#
# Get specific agent details:
#   redis-cli -n 6 HGETALL "worktime:agent:a87a701:2026-02-02"
