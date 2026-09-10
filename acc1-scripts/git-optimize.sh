#!/bin/bash
# Git optimization - runs every 6-8 hours
# Compresses objects, prunes old refs, reduces bloat

set -euo pipefail

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/git-optimize.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

optimize_repo() {
    local DIR="$1"
    local NAME="$2"
    
    cd "$DIR" || return 1
    
    if [ ! -d ".git" ]; then
        return 0
    fi
    
    log "$NAME: Starting optimization..."
    
    # Get stats before
    local SIZE_BEFORE=$(du -sh .git 2>/dev/null | cut -f1)
    local COMMITS_BEFORE=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    
    # Run garbage collection
    git gc --aggressive --prune=now --quiet 2>/dev/null || true
    
    # Repack objects
    git repack -a -d --quiet 2>/dev/null || true
    
    # Prune unreachable objects
    git prune --expire=now 2>/dev/null || true
    
    # Get stats after
    local SIZE_AFTER=$(du -sh .git 2>/dev/null | cut -f1)
    
    log "$NAME: Done. Size: $SIZE_BEFORE → $SIZE_AFTER, Commits: $COMMITS_BEFORE"
}

log "=== GIT OPTIMIZATION START ==="

optimize_repo "/root/workspaces/tools/acc1-scripts" "profile"
optimize_repo "/root/claude-projects" "projects"

log "=== GIT OPTIMIZATION COMPLETE ==="
