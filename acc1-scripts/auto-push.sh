#!/bin/bash
# Auto-push to GitHub every 15 minutes
# Pushes acc1, acc2, and projects to different branches of claude-state repo

set -euo pipefail

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/git-auto-push.log"
MAX_RETRIES=3
RETRY_DELAY=5

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Push with retry logic
push_with_retry() {
    local DIR="$1"
    local BRANCH="$2"
    local NAME="$3"
    local attempt=1

    cd "$DIR" || { log "ERROR: Cannot cd to $DIR"; return 1; }

    # Check if remote exists
    if ! git remote get-url origin &>/dev/null; then
        log "$NAME: No remote configured, skipping"
        return 0
    fi

    # Check for unpushed commits
    local LOCAL_HEAD=$(git rev-parse HEAD 2>/dev/null || echo "none")
    local REMOTE_HEAD=$(git rev-parse origin/$BRANCH 2>/dev/null || echo "none")

    if [ "$LOCAL_HEAD" = "$REMOTE_HEAD" ]; then
        log "$NAME: Up to date, nothing to push"
        return 0
    fi

    # Ensure we're on the right branch — NEVER force-switch, skip instead
    local CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "main")
    if [ "$CURRENT_BRANCH" != "$BRANCH" ]; then
        log "[auto-push] SKIP: $NAME repo on branch '$CURRENT_BRANCH', target was '$BRANCH' — not auto-switching"
        return 0
    fi

    # Count unpushed commits
    local UNPUSHED=$(git rev-list origin/$BRANCH..HEAD 2>/dev/null | wc -l || echo "?")

    while [ $attempt -le $MAX_RETRIES ]; do
        if git push -u origin "$BRANCH" --quiet 2>/dev/null; then
            log "$NAME: Pushed $UNPUSHED commits to $BRANCH"
            return 0
        else
            log "$NAME: Push failed (attempt $attempt/$MAX_RETRIES)"
            sleep $RETRY_DELAY
            ((attempt++))
        fi
    done

    log "ERROR: $NAME failed after $MAX_RETRIES attempts"
    return 1
}

# Push acc1 profile to claude-profile-acc1 repo
push_with_retry "/root/workspaces/tools/acc1-scripts" "main" "acc1"

# Push acc2 profile to claude-profile-acc2 repo
push_with_retry "/root/.claude_alex_acc2" "main" "acc2"

# Push shared config to claude-shared repo
push_with_retry "/root/.claude_shared" "main" "shared"

# Push projects to claude-projects repo
push_with_retry "/root/claude-projects" "main" "projects"

log "--- Push cycle complete ---"
