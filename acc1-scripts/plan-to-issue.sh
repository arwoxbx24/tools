#!/bin/bash
# plan-to-issue.sh — Create a GitHub issue from a plan file
# Usage: bash plan-to-issue.sh [PLAN_FILE]
# If no argument given, uses latest *.md in plans/ directory

set -e

REPO="arwoxbx24/claude-state"
DATA_DIR="/root/workspaces/tools/acc1-scripts/data"
SCRIPTS_DIR="/root/workspaces/tools/acc1-scripts/scripts"
PLANS_DIR="/root/workspaces/tools/acc1-scripts/plans"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/tasks.log"

mkdir -p "$DATA_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE" >&2
}

# Resolve plan file
PLAN_FILE="${1:-}"
if [ -z "$PLAN_FILE" ]; then
    PLAN_FILE=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1)
    if [ -z "$PLAN_FILE" ]; then
        log "ERROR: No plan files found in $PLANS_DIR"
        exit 1
    fi
fi

if [ ! -f "$PLAN_FILE" ]; then
    log "ERROR: Plan file not found: $PLAN_FILE"
    exit 1
fi

log "Using plan file: $PLAN_FILE"

# Extract PLAN_META fields
TITLE=$(grep -m1 '^TITLE: ' "$PLAN_FILE" 2>/dev/null | sed 's/^TITLE: //')
PROJECT=$(grep -m1 '^PROJECT: ' "$PLAN_FILE" 2>/dev/null | sed 's/^PROJECT: //' | tr -d '[:space:]')
EXISTING_ISSUE=$(grep -m1 '^ISSUE: ' "$PLAN_FILE" 2>/dev/null | sed 's/^ISSUE: //' | tr -d '[:space:]')

[ -z "$TITLE" ] && TITLE=$(basename "$PLAN_FILE" .md)
[ -z "$PROJECT" ] && PROJECT="unknown"

# Skip if issue already exists
if [ -n "$EXISTING_ISSUE" ] && [ "$EXISTING_ISSUE" != "0" ] && [[ "$EXISTING_ISSUE" =~ ^[0-9]+$ ]]; then
    log "Issue already exists: #$EXISTING_ISSUE — skipping"
    echo "$EXISTING_ISSUE"
    exit 0
fi

# Extract checklist items outside code blocks
CHECKLIST=$(awk '
/^```/ {
    if (in_code) { in_code = 0 } else { in_code = 1 }
    next
}
in_code { next }
/- \[[ xX]\]/ { print }
' "$PLAN_FILE" 2>/dev/null)

if [ -z "$CHECKLIST" ]; then
    CHECKLIST="- [ ] Task completed"
fi

PLAN_BASENAME=$(basename "$PLAN_FILE")
CREATION_DATE=$(date '+%Y-%m-%d')

BODY="## Plan Reference
File: \`$PLAN_BASENAME\`

## Checklist
$CHECKLIST

---
*Created by plan-to-issue.sh on $CREATION_DATE*"

log "Creating issue: [plan] $TITLE (project: $PROJECT)"

ISSUE_URL=$(gh issue create \
    --repo "$REPO" \
    --title "[plan] $TITLE" \
    --body "$BODY" \
    --label "scope:internal,project:$PROJECT" 2>/dev/null)

ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oE '[0-9]+$')

if [ -z "$ISSUE_NUM" ]; then
    log "ERROR: Failed to extract issue number from URL: $ISSUE_URL"
    exit 1
fi

log "Issue created: #$ISSUE_NUM ($ISSUE_URL)"

# Write ISSUE number back into PLAN_META
sed -i "s/^ISSUE: 0$/ISSUE: $ISSUE_NUM/" "$PLAN_FILE"

# Save to tracking files
echo "$ISSUE_NUM" > "$DATA_DIR/.current-task"
echo "$ISSUE_NUM" > "$DATA_DIR/active-issue.txt"

# Redis: link issue to plan file (7 days TTL)
redis-cli SET "plan:issue-link:$ISSUE_NUM" "$PLAN_FILE" EX 604800 >/dev/null 2>&1 || true

# Invalidate V040 cache
rm -f /tmp/v040-issue-check-cache

# Sync project status
if [ -f "$SCRIPTS_DIR/sync-project-status.sh" ]; then
    bash "$SCRIPTS_DIR/sync-project-status.sh" "$ISSUE_NUM" in-progress 2>/dev/null || true
fi

echo "$ISSUE_NUM"
