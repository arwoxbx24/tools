#!/usr/bin/env bash
# claude-version-status-line.sh — Print one-line Claude Code version status
# Called from claude-expert at startup

STATUS_FILE="/root/workspaces/tools/acc1-scripts/claude-version-status.json"

if [[ ! -f "$STATUS_FILE" ]]; then
    echo "📌 vunknown (pinned) | status: checking..."
    exit 0
fi

# Read fields via jq
PINNED=$(jq -r '.pinned_version // empty' "$STATUS_FILE" 2>/dev/null || true)
CURRENT_VER=$(jq -r '.current_version // "unknown"' "$STATUS_FILE" 2>/dev/null || echo "unknown")
LATEST=$(jq -r '.latest_version // "unknown"' "$STATUS_FILE" 2>/dev/null || echo "unknown")
BUG_FIXED=$(jq -r '.bug_fixed // false' "$STATUS_FILE" 2>/dev/null || echo "false")
RECOMMENDATION=$(jq -r '.recommendation // "STAY_PINNED"' "$STATUS_FILE" 2>/dev/null || echo "STAY_PINNED")
ISSUE_16310=$(jq -r '.issue_16310_state // "unknown"' "$STATUS_FILE" 2>/dev/null || echo "unknown")
ISSUE_41814=$(jq -r '.issue_41814_state // "unknown"' "$STATUS_FILE" 2>/dev/null || echo "unknown")

# Determine combined bug status label
if [[ "$ISSUE_16310" == "CLOSED" && "$ISSUE_41814" == "CLOSED" ]]; then
    BUG_LABEL="FIXED"
elif [[ "$ISSUE_16310" == "unknown" && "$ISSUE_41814" == "unknown" ]]; then
    BUG_LABEL="?"
else
    BUG_LABEL="OPEN"
fi

if [[ "$RECOMMENDATION" == "RUNNING" ]]; then
    echo "✅ v${1:-$CURRENT_VER} (Claude Code)"
elif [[ "$RECOMMENDATION" == "SAFE_TO_UPDATE" ]]; then
    echo "✅ v${PINNED:-unknown} → v${LATEST} AVAILABLE | Ink bug FIXED! Run: npm i -g @anthropic-ai/claude-code@${LATEST}"
else
    echo "📌 v${PINNED:-unknown} (pinned) | latest: v${LATEST} | bug: ${BUG_LABEL}"
fi
