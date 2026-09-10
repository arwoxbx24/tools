#!/bin/bash
# Layer 1: Redis Analyzer
# Runs: every 6 hours via PM2
# Tokens: 0
# Collects: compliance scores, violation counts, trends

set -e

BASE_DIR="/root/workspaces/tools/acc1-scripts"
OUTPUT="$BASE_DIR/data/acs-metrics.json"
HISTORY_DIR="$BASE_DIR/data/acs-history/$(date +%Y-%m-%d)"
TODAY=$(date +%Y-%m-%d)
TIMESTAMP=$(date -Iseconds)

# Ensure directories exist
mkdir -p "$HISTORY_DIR"
mkdir -p "$(dirname "$OUTPUT")"

# Get violation count for today
TOTAL=$(redis-cli -n 2 LLEN "acs:violations:$TODAY" 2>/dev/null || echo 0)
[ -z "$TOTAL" ] && TOTAL=0

# Get per-agent stats with defaults
get_score() {
  local agent=$1
  local score=$(redis-cli -n 2 HGET "acs:stats:agent:$agent" compliance_score 2>/dev/null)
  [ -z "$score" ] && score=100
  echo "$score"
}

OPUS_SCORE=$(get_score opus)
SONNET_SCORE=$(get_score sonnet)
HAIKU_SCORE=$(get_score haiku)

# Get violations per agent today
get_agent_violations() {
  local agent=$1
  local count=$(redis-cli -n 2 LLEN "acs:violations:$agent:$TODAY" 2>/dev/null || echo 0)
  [ -z "$count" ] && count=0
  echo "$count"
}

OPUS_VIOLATIONS=$(get_agent_violations opus)
SONNET_VIOLATIONS=$(get_agent_violations sonnet)
HAIKU_VIOLATIONS=$(get_agent_violations haiku)

# Get top violated rules (top 5)
TOP_RULES_JSON="[]"
RULES_DATA=$(redis-cli -n 2 KEYS "acs:stats:rule:*" 2>/dev/null | while read key; do
  if [ -n "$key" ]; then
    rule=$(echo "$key" | sed 's/acs:stats:rule://')
    count=$(redis-cli -n 2 GET "$key" 2>/dev/null || echo 0)
    [ -n "$count" ] && echo "$count $rule"
  fi
done | sort -rn | head -5)

if [ -n "$RULES_DATA" ]; then
  TOP_RULES_JSON=$(echo "$RULES_DATA" | awk '
    BEGIN { printf "[" }
    NR>1 { printf "," }
    { printf "{\"rule\":\"%s\",\"count\":%d}", $2, $1 }
    END { printf "]" }
  ')
  [ -z "$TOP_RULES_JSON" ] && TOP_RULES_JSON="[]"
fi

# Generate JSON output
cat > "$OUTPUT" << EOF
{
  "timestamp": "$TIMESTAMP",
  "period": "6h",
  "date": "$TODAY",
  "compliance_scores": {
    "opus": $OPUS_SCORE,
    "sonnet": $SONNET_SCORE,
    "haiku": $HAIKU_SCORE
  },
  "violations": {
    "total_today": $TOTAL,
    "by_agent": {
      "opus": $OPUS_VIOLATIONS,
      "sonnet": $SONNET_VIOLATIONS,
      "haiku": $HAIKU_VIOLATIONS
    }
  },
  "top_violated_rules": $TOP_RULES_JSON
}
EOF

# Archive to history
cp "$OUTPUT" "$HISTORY_DIR/metrics-$(date +%H%M).json"

echo "✅ Layer 1: Metrics saved to $OUTPUT"
echo "   Archived to: $HISTORY_DIR/metrics-$(date +%H%M).json"
