#!/usr/bin/env bash
# issue-to-plan-close.sh — cascade close GitHub issue when plan completes
# Usage: issue-to-plan-close.sh <issue_number>
set +e

ISSUE_NUM="$1"
PLANS_DIR="/root/workspaces/tools/acc1-scripts/plans"
DATA_DIR="/root/workspaces/tools/acc1-scripts/data"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/issue-close.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] issue-to-plan-close: $*" | tee -a "$LOG_FILE"
}

# Step 1: validate input
if [[ -z "$ISSUE_NUM" || ! "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
    log "ERROR: argument must be a numeric issue number, got: '$ISSUE_NUM'"
    exit 1
fi

log "Processing issue #$ISSUE_NUM"

# Step 2: find linked plan via Redis
PLAN_FILE="$(redis-cli GET "plan:issue-link:$ISSUE_NUM" 2>/dev/null)"

# Step 3: fallback to grep if Redis returned nothing
if [[ -z "$PLAN_FILE" ]]; then
    PLAN_FILE="$(grep -rl "^ISSUE: $ISSUE_NUM$" "$PLANS_DIR"/*.md 2>/dev/null | head -1)"
fi

if [[ -z "$PLAN_FILE" ]]; then
    log "No plan linked to issue #$ISSUE_NUM — skipping close"
    exit 0
fi

log "Found plan: $PLAN_FILE"

# Step 4: verify plan STATUS is completed
STATUS="$(grep -oP 'STATUS:\s*\K\w+' "$PLAN_FILE" 2>/dev/null | head -1)"
if [[ "$STATUS" != "completed" ]]; then
    log "Plan status is '$STATUS', not completed — skipping close"
    exit 0
fi

# Step 5: sync project status
bash /root/workspaces/tools/acc1-scripts/scripts/sync-project-status.sh "$ISSUE_NUM" done

# Step 6: close the GitHub issue
gh issue close "$ISSUE_NUM" \
    --repo arwoxbx24/claude-state \
    --comment "Plan completed. All checklist items done."
log "Issue #$ISSUE_NUM closed on arwoxbx24/claude-state"

# Step 7: clear tracking files
rm -f "$DATA_DIR/.current-task" "$DATA_DIR/active-issue.txt"
log "Cleared tracking files"

log "Done for issue #$ISSUE_NUM"
