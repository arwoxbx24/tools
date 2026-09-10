#!/bin/bash
# Create GitHub issue and start Claude CLI
# Usage: bash start-task.sh "Task description" [TYPE] [SCOPE] [PROJECT] [--no-claude]
#
# TYPE: feature (default), bug, improvement, docs, research, epic
# SCOPE: internal (default), client, personal
# PROJECT: claude-infra (default for internal), or custom project name
# --no-claude: Only create issue, don't launch Claude

set -e

DESCRIPTION="$1"
TYPE="${2:-feature}"
SCOPE="${3:-internal}"
PROJECT="${4:-}"
NO_CLAUDE=""

# Check for --no-claude flag
for arg in "$@"; do
    if [ "$arg" == "--no-claude" ]; then
        NO_CLAUDE="true"
    fi
done

REPO="arwoxbx24/claude-state"
DATA_DIR="/root/workspaces/tools/acc1-scripts/data"
CURRENT_TASK_FILE="$DATA_DIR/.current-task"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/tasks.log"

mkdir -p "$DATA_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

if [ -z "$DESCRIPTION" ]; then
    echo "Usage: bash start-task.sh \"Task description\" [TYPE] [SCOPE] [PROJECT]"
    echo ""
    echo "Types: feature (default), bug, improvement, docs, research, idea, epic"
    echo "Scopes: internal (default), client, personal"
    echo ""
    echo "Examples:"
    echo "  bash start-task.sh \"Fix hook bug\" bug internal claude-infra"
    echo "  bash start-task.sh \"Export users\" feature client bitrix-migrate"
    echo "  bash start-task.sh \"Audit CRM\" research client bitrix-migrate"
    echo "  bash start-task.sh \"Write user guide\" docs internal claude-infra"
    exit 1
fi

# Validate type (lowercase)
TYPE=$(echo "$TYPE" | tr '[:upper:]' '[:lower:]')
case "$TYPE" in
    bug|feature|improvement|docs|research|epic)
        ;;
    *)
        echo "Invalid type: $TYPE"
        echo "Valid types: bug, feature, improvement, docs, research, epic"
        exit 1
        ;;
esac

# Validate scope
case "$SCOPE" in
    internal|client|personal)
        ;;
    *)
        echo "Invalid scope: $SCOPE"
        echo "Valid scopes: internal, client, personal"
        exit 1
        ;;
esac

# Default project based on scope
if [ -z "$PROJECT" ]; then
    case "$SCOPE" in
        internal) PROJECT="claude-infra" ;;
        client) PROJECT="client-project" ;;
        personal) PROJECT="personal-mvp" ;;
    esac
fi

# Check if already have active task
if bash /root/workspaces/tools/acc1-scripts/scripts/check-active-task.sh --quiet 2>/dev/null; then
    EXISTING=$(cat "$CURRENT_TASK_FILE" 2>/dev/null)
    echo "⚠️  Already have active task: #$EXISTING"
    echo ""
    read -p "Close it and create new? (y/N): " CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        echo "Keeping existing task. Use:"
        echo "  gh issue close $EXISTING --repo $REPO"
        exit 0
    fi

    # Sync status to done BEFORE closing existing task
    bash /root/workspaces/tools/acc1-scripts/scripts/sync-project-status.sh "$EXISTING" done 2>/dev/null || true
    # Then close existing
    gh issue close "$EXISTING" --repo "$REPO" --comment "Closed to start new task" 2>/dev/null || true
    log "Synced and closed previous task #$EXISTING"
fi

log "========================================="
log "CREATING NEW TASK"
log "Type: $TYPE | Scope: $SCOPE | Project: $PROJECT"
log "Description: $DESCRIPTION"

# Build labels
LABELS="scope:$SCOPE"

# Check if project label exists, create if not
if ! gh label list --repo "$REPO" | grep -q "project:$PROJECT"; then
    echo "Creating new project label: project:$PROJECT"
    gh label create "project:$PROJECT" --repo "$REPO" --description "Project: $PROJECT" --color "FBCA04" 2>/dev/null || true
fi
LABELS="$LABELS,project:$PROJECT"

# Create issue
TITLE="[$TYPE] $DESCRIPTION"
BODY="## Context / Контекст

**EN:** $DESCRIPTION

**RU:** [Описание на русском]

**Scope:** $SCOPE | **Project:** $PROJECT

## Checklist
- [ ] Task completed
- [ ] Code tested
- [ ] Documentation updated (if needed)

## Result / Результат
_To be filled on completion_

---
Created: $(date '+%Y-%m-%d %H:%M:%S')
"

echo "Creating GitHub issue..."
ISSUE_URL=$(gh issue create \
    --repo "$REPO" \
    --title "$TITLE" \
    --body "$BODY" \
    --label "$LABELS" \
    2>&1)

# Extract issue number
ISSUE_NUM=$(echo "$ISSUE_URL" | grep -oP 'issues/\K[0-9]+' || echo "")

if [ -z "$ISSUE_NUM" ]; then
    log "ERROR: Failed to create issue"
    echo "$ISSUE_URL"
    exit 1
fi

log "Created issue #$ISSUE_NUM"

# Save current task (both files for compatibility)
echo "$ISSUE_NUM" > "$CURRENT_TASK_FILE"
echo "$ISSUE_NUM" > "$DATA_DIR/active-issue.txt"

# Sync to Projects
echo "Syncing to Projects..."
bash /root/workspaces/tools/acc1-scripts/scripts/sync-project-status.sh "$ISSUE_NUM" in-progress 2>/dev/null || true

# Sync issue type
bash /root/workspaces/tools/acc1-scripts/scripts/sync-issue-types.sh 2>/dev/null || true

log "SUCCESS: Task #$ISSUE_NUM ready"
log "========================================="

echo ""
echo "✅ Task created successfully!"
echo ""
echo "   Issue:   #$ISSUE_NUM"
echo "   Title:   $TITLE"
echo "   Scope:   $SCOPE"
echo "   Project: $PROJECT"
echo "   URL:     $ISSUE_URL"
echo ""

# Launch Claude if not --no-claude
if [ -z "$NO_CLAUDE" ]; then
    echo "Launching Claude CLI..."
    echo "Working on: #$ISSUE_NUM - $DESCRIPTION"
    echo ""

    # Set environment variable for Claude
    export CLAUDE_CURRENT_TASK="$ISSUE_NUM"
    export CLAUDE_TASK_DESCRIPTION="$DESCRIPTION"

    # Launch Claude
    exec claude
else
    echo "Issue created. To start working:"
    echo "  claude"
fi
