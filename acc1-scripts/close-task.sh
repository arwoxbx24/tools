#!/bin/bash
# Close a GitHub issue with structured result summary
# Usage: bash close-task.sh [ISSUE_NUM] [--interactive]
#
# Adds structured summary: pain → solution → result → benefit

set -e

REPO="arwoxbx24/claude-state"
DATA_DIR="/root/workspaces/tools/acc1-scripts/data"
CURRENT_TASK_FILE="$DATA_DIR/.current-task"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/tasks.log"

mkdir -p "$DATA_DIR" "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Parse arguments
ISSUE_NUM="$1"
INTERACTIVE="${2:-}"

# If no issue number, use current task
if [ -z "$ISSUE_NUM" ] || [ "$ISSUE_NUM" == "--interactive" ]; then
    if [ -f "$CURRENT_TASK_FILE" ]; then
        ISSUE_NUM=$(cat "$CURRENT_TASK_FILE")
        INTERACTIVE="$1"
    else
        echo "ERROR: No active task file found"
        echo "Usage: bash close-task.sh [ISSUE_NUM] [--interactive]"
        exit 1
    fi
fi

# Validate issue number
if ! [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
    echo "ERROR: Invalid issue number: $ISSUE_NUM"
    exit 1
fi

# Get issue title
TITLE=$(gh api repos/$REPO/issues/$ISSUE_NUM --jq '.title' 2>/dev/null || echo "Unknown")

log "========================================="
log "CLOSING TASK #$ISSUE_NUM: $TITLE"

# Build structured comment
build_result_comment() {
    local pain="$1"
    local solution="$2"
    local result="$3"
    local benefit="$4"

    cat << EOF
## ✅ Задача завершена / Task Completed

### 😤 Проблема / Pain Point
$pain

### 💡 Решение / Solution
$solution

### 📊 Результат / Result
$result

### 🎯 Выгода / Benefit
$benefit

---
*Closed at $(date '+%Y-%m-%d %H:%M')*
EOF
}

# Check if called with predefined params (from stdin or env)
if [ -n "$CLOSE_PAIN" ] && [ -n "$CLOSE_SOLUTION" ]; then
    COMMENT=$(build_result_comment "$CLOSE_PAIN" "$CLOSE_SOLUTION" "$CLOSE_RESULT" "$CLOSE_BENEFIT")
elif [ "$INTERACTIVE" == "--interactive" ]; then
    echo ""
    echo "=== Structured Result Summary ==="
    echo ""
    read -p "😤 Проблема (что болело): " PAIN
    read -p "💡 Решение (что сделали): " SOLUTION
    read -p "📊 Результат (что получили): " RESULT
    read -p "🎯 Выгода (какая польза): " BENEFIT

    COMMENT=$(build_result_comment "$PAIN" "$SOLUTION" "$RESULT" "$BENEFIT")
else
    # Default minimal comment
    COMMENT="✅ Задача завершена / Task completed"
fi

# Step 1: Sync status to done
echo "Syncing status to done..."
bash /root/workspaces/tools/acc1-scripts/scripts/sync-project-status.sh "$ISSUE_NUM" done 2>/dev/null || true

# Step 2: Close the issue with structured comment
echo "Closing issue..."
gh issue close "$ISSUE_NUM" --repo "$REPO" --comment "$COMMENT"

# Step 3: Clear current task file if this was the active task
if [ -f "$CURRENT_TASK_FILE" ]; then
    ACTIVE=$(cat "$CURRENT_TASK_FILE" 2>/dev/null || echo "")
    if [ "$ACTIVE" == "$ISSUE_NUM" ]; then
        rm -f "$CURRENT_TASK_FILE" "$DATA_DIR/active-issue.txt"
        log "✓ Cleared active task tracking"
    fi
fi

log "SUCCESS: Task #$ISSUE_NUM closed"
log "========================================="

echo ""
echo "✅ Issue #$ISSUE_NUM closed successfully!"
