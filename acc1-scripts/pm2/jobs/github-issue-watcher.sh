#!/bin/bash
# GitHub Issue Watcher — checks Anthropic claude-code issues for closure
# PM2 job: runs daily at 04:30 MSK
# On close: creates alert in data/issue-closed-alerts/ + Redis marker

set -euo pipefail

BASE_DIR="/root/workspaces/tools/acc1-scripts"
WATCHLIST="$BASE_DIR/data/github-issue-watchlist.json"
ALERTS_DIR="$BASE_DIR/data/issue-closed-alerts"
LOG="$BASE_DIR/pm2/logs/github-issue-watcher.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

log "=== GitHub Issue Watcher started ==="

# Validate prerequisites
if ! command -v gh &>/dev/null; then
    log "ERROR: gh CLI not found"
    exit 1
fi

if ! command -v jq &>/dev/null; then
    log "ERROR: jq not found"
    exit 1
fi

if [ ! -f "$WATCHLIST" ]; then
    log "ERROR: Watchlist not found: $WATCHLIST"
    exit 1
fi

mkdir -p "$ALERTS_DIR/processed"

REPO=$(jq -r '.repo' "$WATCHLIST")
OPEN_COUNT=$(jq '[.issues[] | select(.status == "open")] | length' "$WATCHLIST")
CLOSED_NEW=0

log "Repo: $REPO | Open issues to check: $OPEN_COUNT"

if [ "$OPEN_COUNT" -eq 0 ]; then
    log "No open issues to check. Done."
    # Update last_checked
    TMP=$(mktemp)
    jq --arg ts "$(date -Iseconds)" '.last_checked = $ts' "$WATCHLIST" > "$TMP" && mv "$TMP" "$WATCHLIST"
    exit 0
fi

# Check each open issue
for NUMBER in $(jq -r '.issues[] | select(.status == "open") | .number' "$WATCHLIST"); do
    log "Checking issue #$NUMBER..."

    # Fetch issue state from GitHub
    ISSUE_DATA=$(gh issue view "$NUMBER" --repo "$REPO" --json state,closedAt,stateReason,title 2>&1) || {
        log "WARNING: Failed to fetch issue #$NUMBER: $ISSUE_DATA"
        continue
    }

    STATE=$(echo "$ISSUE_DATA" | jq -r '.state')

    if [ "$STATE" = "CLOSED" ]; then
        CLOSED_AT=$(echo "$ISSUE_DATA" | jq -r '.closedAt // "unknown"')
        STATE_REASON=$(echo "$ISSUE_DATA" | jq -r '.stateReason // "unknown"')
        TITLE=$(echo "$ISSUE_DATA" | jq -r '.title // "unknown"')
        PRIORITY=$(jq -r --argjson n "$NUMBER" '.issues[] | select(.number == $n) | .priority' "$WATCHLIST")
        ACTION=$(jq -r --argjson n "$NUMBER" '.issues[] | select(.number == $n) | .action_on_close' "$WATCHLIST")

        log "CLOSED: #$NUMBER — $TITLE (reason: $STATE_REASON, at: $CLOSED_AT)"

        # Update watchlist: status → closed
        TMP=$(mktemp)
        jq --argjson n "$NUMBER" --arg r "$STATE_REASON" --arg ca "$CLOSED_AT" \
            '(.issues[] | select(.number == $n)) |= . + {status: "closed", closed_at: $ca, state_reason: $r}' \
            "$WATCHLIST" > "$TMP" && mv "$TMP" "$WATCHLIST"

        # Create alert file
        ALERT_FILE="$ALERTS_DIR/${NUMBER}.json"
        jq -n \
            --argjson number "$NUMBER" \
            --arg title "$TITLE" \
            --arg priority "$PRIORITY" \
            --arg state_reason "$STATE_REASON" \
            --arg closed_at "$CLOSED_AT" \
            --arg action "$ACTION" \
            --arg detected_at "$(date -Iseconds)" \
            '{number: $number, title: $title, priority: $priority, state_reason: $state_reason, closed_at: $closed_at, action_on_close: $action, detected_at: $detected_at}' \
            > "$ALERT_FILE"

        log "Alert created: $ALERT_FILE"

        # Redis marker (7 days TTL)
        redis-cli SET "github:issue:closed:${NUMBER}" "{\"number\":${NUMBER},\"title\":\"${TITLE}\",\"reason\":\"${STATE_REASON}\",\"closed_at\":\"${CLOSED_AT}\"}" EX 604800 >/dev/null 2>&1 || \
            log "WARNING: Failed to set Redis marker for #$NUMBER"

        ((CLOSED_NEW++))
    else
        log "OPEN: #$NUMBER — still open"
    fi
done

# Update last_checked timestamp
TMP=$(mktemp)
jq --arg ts "$(date -Iseconds)" '.last_checked = $ts' "$WATCHLIST" > "$TMP" && mv "$TMP" "$WATCHLIST"

log "=== Done: $CLOSED_NEW newly closed issues detected ==="

if [ "$CLOSED_NEW" -gt 0 ]; then
    log "ACTION REQUIRED: PE should check data/issue-closed-alerts/ on next session start"
fi

exit 0
