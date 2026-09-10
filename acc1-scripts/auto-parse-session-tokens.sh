#!/bin/bash
# CASTLE: Auto-parse all session JSONL files for token usage
# Run: PM2 cron every 5 minutes OR manually
# Stores in Redis DB 5

REDIS_DB=5
TODAY=$(date +%Y-%m-%d)
TODAY_START=$(date -d "$TODAY" +%s)

# Track totals
TOTAL_INPUT=0
TOTAL_OUTPUT=0
TOTAL_CACHE=0

# Process all JSONL files in projects directory
PROJECTS_DIR="/root/workspaces/tools/acc1-scripts/projects"

for jsonl in "$PROJECTS_DIR"/*/*.jsonl; do
    [ ! -f "$jsonl" ] && continue

    # Check if file was modified today
    FILE_MTIME=$(stat -c %Y "$jsonl" 2>/dev/null || echo 0)
    [ "$FILE_MTIME" -lt "$TODAY_START" ] && continue

    # Extract token counts
    INPUT=$(grep -o '"input_tokens":[0-9]*' "$jsonl" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
    OUTPUT=$(grep -o '"output_tokens":[0-9]*' "$jsonl" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
    CACHE_READ=$(grep -o '"cache_read_input_tokens":[0-9]*' "$jsonl" 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')

    TOTAL_INPUT=$((TOTAL_INPUT + INPUT))
    TOTAL_OUTPUT=$((TOTAL_OUTPUT + OUTPUT))
    TOTAL_CACHE=$((TOTAL_CACHE + CACHE_READ))
done

# Store totals in Redis
redis-cli -n $REDIS_DB HSET "castle:tokens:$TODAY" "input" "$TOTAL_INPUT" > /dev/null 2>&1
redis-cli -n $REDIS_DB HSET "castle:tokens:$TODAY" "output" "$TOTAL_OUTPUT" > /dev/null 2>&1
redis-cli -n $REDIS_DB HSET "castle:tokens:$TODAY" "cache" "$TOTAL_CACHE" > /dev/null 2>&1
redis-cli -n $REDIS_DB EXPIRE "castle:tokens:$TODAY" 604800 > /dev/null 2>&1

# Output summary
echo "CASTLE Token Parser: input=$TOTAL_INPUT, output=$TOTAL_OUTPUT, cache=$TOTAL_CACHE"

exit 0
