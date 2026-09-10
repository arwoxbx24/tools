#!/bin/bash
# Check if there's an active GitHub issue for current work
# Usage: bash check-active-task.sh [--quiet]
#
# Exit codes:
#   0 = Active task exists
#   1 = No active task

REPO="arwoxbx24/claude-state"
DATA_DIR="/root/workspaces/tools/acc1-scripts/data"
CURRENT_TASK_FILE="$DATA_DIR/.current-task"
QUIET=""

if [ "$1" == "--quiet" ]; then
    QUIET="true"
fi

mkdir -p "$DATA_DIR"

# Check saved current task first
if [ -f "$CURRENT_TASK_FILE" ]; then
    SAVED_ISSUE=$(cat "$CURRENT_TASK_FILE" 2>/dev/null)
    if [ -n "$SAVED_ISSUE" ]; then
        # Verify issue still exists and is in-progress
        STATUS=$(gh issue view "$SAVED_ISSUE" --repo "$REPO" --json state,labels -q '.state + ":" + ([.labels[].name] | join(","))' 2>/dev/null)
        if echo "$STATUS" | grep -q "OPEN.*status-in-progress"; then
            if [ -z "$QUIET" ]; then
                TITLE=$(gh issue view "$SAVED_ISSUE" --repo "$REPO" --json title -q '.title' 2>/dev/null)
                echo "✅ Active task: #$SAVED_ISSUE"
                echo "   Title: $TITLE"
                echo "   URL: https://github.com/$REPO/issues/$SAVED_ISSUE"
            fi
            exit 0
        fi
    fi
fi

# Check GitHub for any in-progress issues
ACTIVE=$(gh issue list --repo "$REPO" --label "status-in-progress" --json number,title --limit 1 2>/dev/null)
ISSUE_NUM=$(echo "$ACTIVE" | jq -r '.[0].number // empty' 2>/dev/null)

if [ -n "$ISSUE_NUM" ]; then
    # Save for future checks
    echo "$ISSUE_NUM" > "$CURRENT_TASK_FILE"

    if [ -z "$QUIET" ]; then
        TITLE=$(echo "$ACTIVE" | jq -r '.[0].title' 2>/dev/null)
        echo "✅ Active task: #$ISSUE_NUM"
        echo "   Title: $TITLE"
        echo "   URL: https://github.com/$REPO/issues/$ISSUE_NUM"
    fi
    exit 0
fi

# No active task
if [ -z "$QUIET" ]; then
    echo "❌ No active task found!"
    echo ""
    echo "Create one with:"
    echo "  bash /root/workspaces/tools/acc1-scripts/scripts/start-task.sh \"Task description\" [EPIC|FIX]"
    echo ""
    echo "Or manually:"
    echo "  gh issue create --repo $REPO --title \"Description\" --label \"status-in-progress\""
fi

# Clear stale current task file
rm -f "$CURRENT_TASK_FILE" 2>/dev/null

exit 1
