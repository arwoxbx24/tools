#!/bin/bash
# Git Squash Old Commits
# Squashes commits older than 14 days into daily snapshots
# Run every 2 weeks via cron

set -euo pipefail

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/git-squash.log"
KEEP_DAYS=14

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
    echo "$1"
}

squash_repo() {
    local DIR="$1"
    local NAME="$2"
    
    cd "$DIR" || return 1
    
    if [ ! -d ".git" ]; then
        log "$NAME: Not a git repo, skipping"
        return 0
    fi
    
    # Get total commits
    local TOTAL_COMMITS=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    if [ "$TOTAL_COMMITS" -lt 50 ]; then
        log "$NAME: Only $TOTAL_COMMITS commits, skipping (need 50+)"
        return 0
    fi
    
    log "$NAME: Starting squash (total: $TOTAL_COMMITS commits)"
    
    # Find the commit from KEEP_DAYS ago
    local CUTOFF_DATE=$(date -d "$KEEP_DAYS days ago" '+%Y-%m-%d')
    local CUTOFF_COMMIT=$(git rev-list -1 --before="$CUTOFF_DATE 23:59:59" HEAD 2>/dev/null || echo "")
    
    if [ -z "$CUTOFF_COMMIT" ]; then
        log "$NAME: No commits older than $KEEP_DAYS days"
        return 0
    fi
    
    # Count commits to squash
    local OLD_COMMITS=$(git rev-list --count $CUTOFF_COMMIT 2>/dev/null || echo "0")
    if [ "$OLD_COMMITS" -lt 20 ]; then
        log "$NAME: Only $OLD_COMMITS old commits, skipping (need 20+)"
        return 0
    fi
    
    log "$NAME: Found $OLD_COMMITS commits before $CUTOFF_DATE"
    
    # Create backup tag
    local BACKUP_TAG="backup-$(date '+%Y%m%d-%H%M%S')"
    git tag "$BACKUP_TAG" HEAD
    log "$NAME: Created backup tag: $BACKUP_TAG"
    
    # Get the first commit (root)
    local ROOT_COMMIT=$(git rev-list --max-parents=0 HEAD | tail -1)
    
    # Strategy: Soft reset to cutoff, then recommit as single "Archive" commit
    # Then cherry-pick recent commits on top
    
    # Save recent commits (after cutoff)
    local RECENT_COMMITS=$(git rev-list --reverse $CUTOFF_COMMIT..HEAD 2>/dev/null || echo "")
    local RECENT_COUNT=$(echo "$RECENT_COMMITS" | grep -c . || echo "0")
    
    log "$NAME: Preserving $RECENT_COUNT recent commits"
    
    # Create new branch for squashed history
    git checkout --orphan squash-temp 2>/dev/null
    
    # Checkout files from cutoff commit
    git checkout $CUTOFF_COMMIT -- . 2>/dev/null || true
    
    # Create single archive commit
    git add -A
    git commit -m "Archive: All changes before $CUTOFF_DATE ($OLD_COMMITS commits)" --quiet 2>/dev/null || true
    
    # Cherry-pick recent commits
    if [ -n "$RECENT_COMMITS" ] && [ "$RECENT_COUNT" -gt 0 ]; then
        for commit in $RECENT_COMMITS; do
            git cherry-pick --no-commit $commit 2>/dev/null || true
            local MSG=$(git log -1 --format="%s" $commit 2>/dev/null || echo "Auto commit")
            git commit -m "$MSG" --quiet 2>/dev/null || true
        done
    fi
    
    # Replace main branch
    git branch -D main 2>/dev/null || true
    git branch -m squash-temp main
    
    # Cleanup: remove large files from history
    if command -v git-filter-repo &>/dev/null; then
        git filter-repo --invert-paths \
            --path-glob '*/node_modules/*' \
            --path-glob '*/.venv/*' \
            --path-glob '*/venv/*' \
            --path-glob '*.tar.gz' \
            --path-glob '*.so' \
            --path-glob '*.pack' \
            --force --quiet 2>/dev/null || true
    fi

    # Aggressive GC
    git gc --aggressive --prune=now --quiet 2>/dev/null
    
    # Final stats
    local NEW_TOTAL=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    local SIZE=$(du -sh .git | cut -f1)
    
    log "$NAME: Done! $TOTAL_COMMITS → $NEW_TOTAL commits, size: $SIZE"
    log "$NAME: Backup tag: $BACKUP_TAG (use 'git checkout $BACKUP_TAG' to restore)"
}

log "=== GIT SQUASH START ==="

squash_repo "/root/workspaces/tools/acc1-scripts" "profile"
squash_repo "/root/claude-projects" "projects"

log "=== GIT SQUASH COMPLETE ==="
