#!/bin/bash
# Mirror sync rules from Expert (parent) to all child accounts
# Usage: bash sync-rules-to-children.sh [--dry-run]

set -e

PARENT_DIR="/root/workspaces/tools/acc1-scripts"
CHILDREN=("/root/.claude_alex_acc2")  # Add more children here if needed
LOG_FILE="$PARENT_DIR/logs/sync-rules.log"
DRY_RUN=""

if [ "$1" == "--dry-run" ]; then
    DRY_RUN="--dry-run"
    echo "[DRY RUN MODE]"
fi

mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "========================================="
log "SYNC RULES START"

# Directories and files to sync
SYNC_DIRS=(
    "operations"
    "reference"
    "skills"
    "scripts"
    "config"
    "docs"
    "hooks"
)

SYNC_FILES=(
    # "CLAUDE.md"  # EXCLUDED: ALEX has own EXECUTOR role, Expert has ARCHITECT role
    "NAVIGATION.md"
    ".projects-config"
)

# Sync to each child
for CHILD_DIR in "${CHILDREN[@]}"; do
    log "Syncing to: $CHILD_DIR"

    # Create directories if not exist
    for dir in "${SYNC_DIRS[@]}"; do
        mkdir -p "$CHILD_DIR/$dir"
    done

    # Sync directories
    for dir in "${SYNC_DIRS[@]}"; do
        if [ -d "$PARENT_DIR/$dir" ]; then
            log "  Syncing directory: $dir/"
            rsync -av --delete $DRY_RUN \
                "$PARENT_DIR/$dir/" \
                "$CHILD_DIR/$dir/" 2>&1 | grep -v "^$" | head -5 || true
        fi
    done

    # Sync individual files
    for file in "${SYNC_FILES[@]}"; do
        if [ -f "$PARENT_DIR/$file" ]; then
            log "  Syncing file: $file"
            rsync -av $DRY_RUN \
                "$PARENT_DIR/$file" \
                "$CHILD_DIR/$file" 2>&1 | grep -v "^$" || true
        fi
    done

    log "Completed sync to: $CHILD_DIR"
done

log "SYNC RULES COMPLETE"
log "========================================="
