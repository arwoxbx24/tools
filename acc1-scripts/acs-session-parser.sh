#!/bin/bash
# Layer 3: Session Log Parser
# Runs: daily at 3 AM via PM2
# Tokens: 0
# Collects: error patterns, token usage, failed tasks

set -e

BASE_DIR="/root/workspaces/tools/acc1-scripts"
OUTPUT="$BASE_DIR/data/acs-sessions.json"
HISTORY_DIR="$BASE_DIR/data/acs-history/$(date +%Y-%m-%d)"
PROJECTS_DIR="$BASE_DIR/projects"
TIMESTAMP=$(date -Iseconds)
YESTERDAY=$(date -d 'yesterday' +%Y-%m-%d 2>/dev/null || date -v-1d +%Y-%m-%d)

mkdir -p "$HISTORY_DIR"
mkdir -p "$(dirname "$OUTPUT")"

# Find recent session files (last 24h)
SESSIONS_COUNT=0
TOTAL_TOKENS=0
ERROR_COUNT=0
TOOL_FAILURES=""

if [ -d "$PROJECTS_DIR" ]; then
  # Count sessions modified in last 24h
  SESSIONS_COUNT=$(find "$PROJECTS_DIR" -name "*.jsonl" -mtime -1 2>/dev/null | wc -l || echo 0)

  # Parse each session for errors and token usage
  while IFS= read -r file; do
    # Count errors
    errors=$(grep -c '"error"' "$file" 2>/dev/null || echo 0)
    ERROR_COUNT=$((ERROR_COUNT + errors))

    # Sum tokens (rough estimate from usage fields)
    tokens=$(grep -oP '"input_tokens":\s*\K\d+' "$file" 2>/dev/null | awk '{sum+=$1} END {print sum+0}')
    [ -n "$tokens" ] && [ "$tokens" -gt 0 ] && TOTAL_TOKENS=$((TOTAL_TOKENS + tokens))

    # Find tool failures
    grep -oP '"tool":\s*"\K[^"]+(?=.*error)' "$file" 2>/dev/null >> /tmp/tool_failures_$$ || true
  done < <(find "$PROJECTS_DIR" -name "*.jsonl" -mtime -1 2>/dev/null)

  # Get unique tool failures
  if [ -f /tmp/tool_failures_$$ ]; then
    TOOL_FAILURES=$(sort /tmp/tool_failures_$$ | uniq -c | sort -rn | head -5 | \
      awk 'BEGIN{printf "["} NR>1{printf ","} {printf "{\"tool\":\"%s\",\"count\":%d}", $2, $1} END{printf "]"}')
    rm -f /tmp/tool_failures_$$
  fi
fi

[ -z "$TOOL_FAILURES" ] && TOOL_FAILURES="[]"
[ -z "$SESSIONS_COUNT" ] && SESSIONS_COUNT=0
[ -z "$TOTAL_TOKENS" ] && TOTAL_TOKENS=0
[ -z "$ERROR_COUNT" ] && ERROR_COUNT=0

# Generate JSON output
cat > "$OUTPUT" << EOF
{
  "timestamp": "$TIMESTAMP",
  "period": "24h",
  "date": "$YESTERDAY",
  "sessions_analyzed": $SESSIONS_COUNT,
  "token_usage": {
    "total_input": $TOTAL_TOKENS
  },
  "errors": {
    "total": $ERROR_COUNT,
    "tool_failures": $TOOL_FAILURES
  }
}
EOF

# Archive to history
cp "$OUTPUT" "$HISTORY_DIR/sessions.json"

echo "✅ Layer 3: Session data saved to $OUTPUT"
