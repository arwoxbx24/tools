#!/usr/bin/env bash
# claude-version-check.sh — Claude Code version monitoring
# Checks current vs latest version and GitHub issue status
# Run every 6 hours via cron

set -euo pipefail

PINNED_VERSION="$(claude --version 2>/dev/null | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo 'unknown')"
STATUS_FILE="/root/workspaces/tools/acc1-scripts/claude-version-status.json"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/version-check.log"
NOTIFY_SCRIPT="/root/workspaces/tools/acc1-scripts/scripts/claude-version-pe-notify.sh"

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*" >> "$LOG_FILE"
}

log "Starting version check"

# Get current installed version
CURRENT_VERSION=$(claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
log "Current installed: $CURRENT_VERSION"

# Get latest available version from npm
LATEST_VERSION=$(npm view @anthropic-ai/claude-code version 2>/dev/null || echo "unknown")
log "Latest on npm: $LATEST_VERSION"

# Check GitHub issue #16310
ISSUE_16310_STATE="unknown"
if ISSUE_16310_JSON=$(gh issue view 16310 --repo anthropics/claude-code --json state,title 2>/dev/null); then
    ISSUE_16310_STATE=$(echo "$ISSUE_16310_JSON" | jq -r '.state' 2>/dev/null || echo "unknown")
    ISSUE_16310_TITLE=$(echo "$ISSUE_16310_JSON" | jq -r '.title' 2>/dev/null || echo "")
    log "Issue #16310: $ISSUE_16310_STATE — $ISSUE_16310_TITLE"
else
    log "Warning: could not fetch issue #16310"
fi

# Check GitHub issue #41814
ISSUE_41814_STATE="unknown"
if ISSUE_41814_JSON=$(gh issue view 41814 --repo anthropics/claude-code --json state,title 2>/dev/null); then
    ISSUE_41814_STATE=$(echo "$ISSUE_41814_JSON" | jq -r '.state' 2>/dev/null || echo "unknown")
    ISSUE_41814_TITLE=$(echo "$ISSUE_41814_JSON" | jq -r '.title' 2>/dev/null || echo "")
    log "Issue #41814: $ISSUE_41814_STATE — $ISSUE_41814_TITLE"
else
    log "Warning: could not fetch issue #41814"
fi

# Determine bug_fixed: both issues must be CLOSED
BUG_FIXED="false"
if [[ "$ISSUE_16310_STATE" == "CLOSED" && "$ISSUE_41814_STATE" == "CLOSED" ]]; then
    BUG_FIXED="true"
    log "Bug appears fixed — both issues closed"
fi

# Determine recommendation
RECOMMENDATION="STAY_PINNED"
if [[ "$BUG_FIXED" == "true" && "$LATEST_VERSION" != "unknown" ]]; then
    # Compare versions: safe to update if latest > pinned
    LATEST_MAJOR=$(echo "$LATEST_VERSION" | cut -d. -f1)
    LATEST_MINOR=$(echo "$LATEST_VERSION" | cut -d. -f2)
    LATEST_PATCH=$(echo "$LATEST_VERSION" | cut -d. -f3)
    PINNED_MAJOR=$(echo "$PINNED_VERSION" | cut -d. -f1)
    PINNED_MINOR=$(echo "$PINNED_VERSION" | cut -d. -f2)
    PINNED_PATCH=$(echo "$PINNED_VERSION" | cut -d. -f3)

    if (( LATEST_MAJOR > PINNED_MAJOR )) || \
       (( LATEST_MAJOR == PINNED_MAJOR && LATEST_MINOR > PINNED_MINOR )) || \
       (( LATEST_MAJOR == PINNED_MAJOR && LATEST_MINOR == PINNED_MINOR && LATEST_PATCH > PINNED_PATCH )); then
        RECOMMENDATION="SAFE_TO_UPDATE"
        log "Recommendation: SAFE_TO_UPDATE to $LATEST_VERSION"
    fi
fi

CHECKED_AT=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

# Write status JSON
jq -n \
    --arg pinned "$PINNED_VERSION" \
    --arg current "$CURRENT_VERSION" \
    --arg latest "$LATEST_VERSION" \
    --arg state16310 "$ISSUE_16310_STATE" \
    --arg state41814 "$ISSUE_41814_STATE" \
    --argjson bug_fixed "$BUG_FIXED" \
    --arg checked_at "$CHECKED_AT" \
    --arg recommendation "$RECOMMENDATION" \
    '{
        pinned_version: $pinned,
        current_version: $current,
        latest_version: $latest,
        issue_16310_state: $state16310,
        issue_41814_state: $state41814,
        bug_fixed: $bug_fixed,
        checked_at: $checked_at,
        recommendation: $recommendation
    }' > "$STATUS_FILE"

log "Status written to $STATUS_FILE"

# Trigger PE notification if bug is now fixed
if [[ "$BUG_FIXED" == "true" && -x "$NOTIFY_SCRIPT" ]]; then
    "$NOTIFY_SCRIPT" "$LATEST_VERSION"
    log "PE notification script executed"
fi

log "Version check complete. recommendation=$RECOMMENDATION"
