#!/bin/bash
# auto-cleanup.sh - Automatic cleanup of debug and logs directories
# Run: ./scripts/auto-cleanup.sh [--dry-run]
# Cron: 0 3 */3 * * /bin/bash /root/workspaces/tools/acc1-scripts/scripts/auto-cleanup.sh

set -euo pipefail

# Configuration
RETENTION_DAYS=3
DRY_RUN=false
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/cleanup.log"

# Directories to clean (3 days retention)
CLEANUP_DIRS=(
    "/root/workspaces/tools/acc1-scripts/debug"
    "/root/workspaces/tools/acc1-scripts/logs"
    "/root/workspaces/tools/acc1-scripts/cache"
    "/root/workspaces/tools/acc1-scripts/downloads"
    "/root/.claude_alex_acc2/debug"
    "/root/.claude_alex_acc2/logs"
    "/root/.claude_alex_acc2/cache"
)

# Agent reports directories (7 days retention, .md only)
CLEANUP_AGENT_REPORTS=(
    "/root/workspaces/tools/acc1-scripts/agent-reports"
)

# Directories with longer retention (7 days) - session data
CLEANUP_DIRS_7DAYS=(
    "/root/workspaces/tools/acc1-scripts/file-history"
    "/root/workspaces/tools/acc1-scripts/shell-snapshots"
    "/root/workspaces/tools/acc1-scripts/paste-cache"
    "/root/workspaces/tools/acc1-scripts/session-env"
    "/root/workspaces/tools/acc1-scripts/todos"
    "/root/.claude_alex_acc2/file-history"
    "/root/.claude_alex_acc2/shell-snapshots"
    "/root/.claude_alex_acc2/paste-cache"
    "/root/.claude_alex_acc2/session-env"
    "/root/.claude_alex_acc2/todos"
)

# Files to preserve (never delete)
PRESERVE_PATTERNS=(
    "cleanup.log"
    "security-blocked.log"
    "bash-audit.log"
)

# Parse arguments
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    echo "[DRY-RUN MODE] No files will be deleted"
fi

# Logging function
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# Build exclude pattern for find
build_exclude() {
    local excludes=""
    for pattern in "${PRESERVE_PATTERNS[@]}"; do
        excludes="$excludes ! -name '$pattern'"
    done
    echo "$excludes"
}

# Main cleanup function
cleanup_dir() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log "SKIP: Directory does not exist: $dir"
        return 0
    fi

    # Count files before cleanup
    local before=$(find "$dir" -type f 2>/dev/null | wc -l)

    # Find and delete old files (excluding preserved ones)
    local deleted=0
    while IFS= read -r -d '' file; do
        # Check if file matches any preserve pattern
        local preserve=false
        for pattern in "${PRESERVE_PATTERNS[@]}"; do
            if [[ "$(basename "$file")" == "$pattern" ]]; then
                preserve=true
                break
            fi
        done

        if [[ "$preserve" == false ]]; then
            if [[ "$DRY_RUN" == true ]]; then
                echo "  Would delete: $file"
            else
                rm -f "$file" 2>/dev/null && ((deleted++)) || true
            fi
        fi
    done < <(find "$dir" -type f -mtime +$RETENTION_DAYS -print0 2>/dev/null)

    # Remove empty directories
    if [[ "$DRY_RUN" == false ]]; then
        find "$dir" -type d -empty -delete 2>/dev/null || true
    fi

    local after=$(find "$dir" -type f 2>/dev/null | wc -l)
    log "CLEANED: $dir | Before: $before | Deleted: $deleted | After: $after"
}

# Calculate space before cleanup
space_before() {
    local total=0
    for dir in "${CLEANUP_DIRS[@]}"; do
        if [[ -d "$dir" ]]; then
            local size=$(du -sb "$dir" 2>/dev/null | cut -f1)
            total=$((total + size))
        fi
    done
    echo $total
}

# Main execution
log "=== Auto-cleanup started (retention: ${RETENTION_DAYS} days) ==="

BEFORE_SIZE=$(space_before)

# Clean 3-day directories
for dir in "${CLEANUP_DIRS[@]}"; do
    cleanup_dir "$dir"
done

# Clean 7-day directories (session data)
log "=== Cleaning session directories (7 days retention) ==="
RETENTION_DAYS=7
for dir in "${CLEANUP_DIRS_7DAYS[@]}"; do
    cleanup_dir "$dir"
done
RETENTION_DAYS=3  # Reset

# Agent reports cleanup (7-day retention, .md only)
log "=== Cleaning agent-reports (.md files, 7 days retention) ==="
for dir in "${CLEANUP_AGENT_REPORTS[@]}"; do
    if [[ -d "$dir" ]]; then
        ar_before=$(find "$dir" -name "*.md" -type f 2>/dev/null | wc -l)
        if [[ "$DRY_RUN" == true ]]; then
            find "$dir" -name "*.md" -mtime +7 -type f 2>/dev/null | while read -r f; do echo "  Would delete: $f"; done
        else
            find "$dir" -name "*.md" -mtime +7 -delete 2>/dev/null || true
        fi
        ar_after=$(find "$dir" -name "*.md" -type f 2>/dev/null | wc -l)
        ar_deleted=$((ar_before - ar_after))
        log "CLEANED agent-reports: $dir | Before: $ar_before | Deleted: $ar_deleted | After: $ar_after"
    else
        log "SKIP: Directory does not exist: $dir"
    fi
done

AFTER_SIZE=$(space_before)
FREED=$((BEFORE_SIZE - AFTER_SIZE))
FREED_MB=$((FREED / 1024 / 1024))

log "=== Cleanup complete | Freed: ${FREED_MB} MB ==="

# Exit with success
exit 0
