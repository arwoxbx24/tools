#!/bin/bash
# Layer 2: Hook Log Aggregator
# Runs: every hour via PM2
# Tokens: 0
# Collects: security blocks, hook triggers, bash command patterns

set -e

BASE_DIR="/root/workspaces/tools/acc1-scripts"
OUTPUT="$BASE_DIR/data/acs-hooks.json"
HISTORY_DIR="$BASE_DIR/data/acs-history/$(date +%Y-%m-%d)"
LOGS_DIR="$BASE_DIR/logs"
TIMESTAMP=$(date -Iseconds)
HOUR_AGO=$(date -d '1 hour ago' '+%Y-%m-%d %H:%M' 2>/dev/null || date -v-1H '+%Y-%m-%d %H:%M')

mkdir -p "$HISTORY_DIR"
mkdir -p "$(dirname "$OUTPUT")"

# Count security blocks in last hour
SECURITY_LOG="$LOGS_DIR/security-blocked.log"
SECURITY_BLOCKS=0
BLOCKED_COMMANDS="[]"
if [ -f "$SECURITY_LOG" ]; then
  SECURITY_BLOCKS=$(grep -c "$(date +%Y-%m-%d)" "$SECURITY_LOG" 2>/dev/null || echo 0)
  BLOCKED_COMMANDS=$(tail -20 "$SECURITY_LOG" 2>/dev/null | \
    grep -oP 'command:\s*\K[^|]+' | \
    head -5 | \
    awk 'BEGIN{printf "["} NR>1{printf ","} {gsub(/"/, "\\\""); printf "\"%s\"", $0} END{printf "]"}')
  [ -z "$BLOCKED_COMMANDS" ] && BLOCKED_COMMANDS="[]"
fi

# Count bash commands in last hour
BASH_LOG="$LOGS_DIR/bash-audit.log"
BASH_TOTAL=0
BASH_UNIQUE=0
TOP_COMMANDS="[]"
if [ -f "$BASH_LOG" ]; then
  # Get today's commands
  TODAY_COMMANDS=$(grep "$(date +%Y-%m-%d)" "$BASH_LOG" 2>/dev/null || true)
  if [ -n "$TODAY_COMMANDS" ]; then
    BASH_TOTAL=$(echo "$TODAY_COMMANDS" | wc -l)
    BASH_UNIQUE=$(echo "$TODAY_COMMANDS" | awk -F'|' '{print $NF}' | sort -u | wc -l)
    TOP_COMMANDS=$(echo "$TODAY_COMMANDS" | \
      awk -F'|' '{print $NF}' | \
      awk '{print $1}' | \
      sort | uniq -c | sort -rn | head -5 | \
      awk 'BEGIN{printf "["} NR>1{printf ","} {gsub(/"/, "\\\"", $2); printf "\"%s\"", $2} END{printf "]"}')
  fi
  [ -z "$TOP_COMMANDS" ] && TOP_COMMANDS="[]"
fi

# Generate JSON output
cat > "$OUTPUT" << EOF
{
  "timestamp": "$TIMESTAMP",
  "period": "1h",
  "security_blocks": {
    "total_today": $SECURITY_BLOCKS,
    "recent_commands": $BLOCKED_COMMANDS
  },
  "bash_commands": {
    "total_today": $BASH_TOTAL,
    "unique_today": $BASH_UNIQUE,
    "top_commands": $TOP_COMMANDS
  }
}
EOF

# Archive to history
cp "$OUTPUT" "$HISTORY_DIR/hooks-$(date +%H%M).json"

echo "✅ Layer 2: Hook data saved to $OUTPUT"
