#!/usr/bin/env bash
set -euo pipefail

PROFILE_DIR="/root/workspaces/tools/acc1-scripts"
MARKER_FILE="$PROFILE_DIR/data/anthropic-incidents.txt"
API_URL="https://status.claude.com/api/v2"

# Step 1: Quick check
STATUS=$(curl -sf --max-time 10 "$API_URL/status.json" 2>/dev/null) || exit 0
INDICATOR=$(echo "$STATUS" | jq -r '.status.indicator' 2>/dev/null) || exit 0

if [[ "$INDICATOR" == "none" ]]; then
    rm -f "$MARKER_FILE"
    exit 0
fi

# Step 2: Get unresolved incidents
INCIDENTS=$(curl -sf --max-time 10 "$API_URL/incidents/unresolved.json" 2>/dev/null) || exit 0
COUNT=$(echo "$INCIDENTS" | jq -r '.incidents | length' 2>/dev/null) || exit 0

if [[ "$COUNT" -eq 0 ]]; then
    rm -f "$MARKER_FILE"
    exit 0
fi

# Step 3: Build summary
SUMMARY=$(echo "$INCIDENTS" | jq -r '
  .incidents[:3] | .[] |
  "- \(.impact | ascii_upcase): \(.name) [\(.status)] → \([.components[].name] | join(", "))"
' 2>/dev/null) || exit 0

# Step 4: Write marker
{
    printf '⚠️ Anthropic Status [%s]:\n' "$(date -u +"%Y-%m-%d %H:%M UTC")"
    printf '%s\n' "${SUMMARY}"
    printf 'Hint: on 529/503 errors consider Sonnet fallback\n'
} > "$MARKER_FILE"

exit 0
