#!/bin/bash
# tx-cleanup.sh — Remove stale temporary transaction projects (.t-*) older than 72h
# Skip directories where .tx-meta.json has "promoted":true
# Usage: tx-cleanup.sh [--dry]
# PM2: cron_restart "0 3 * * *", autorestart false

set -uo pipefail

# ── Config ──────────────────────────────────────────────────────────────
PROJECTS_ROOT="/root/workspaces/projects"
LOG_FILE="/var/log/tx-cleanup.log"
LOG_MAX_LINES=1000
AGE_DAYS=2          # find -mtime +2 = older than 48h (>2 full days = 72h boundary)
DRY_RUN=false

# ── Argument parsing ─────────────────────────────────────────────────────
for arg in "$@"; do
    case "$arg" in
        --dry) DRY_RUN=true ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# ── Logging ──────────────────────────────────────────────────────────────
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local lines
        lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
        if (( lines > LOG_MAX_LINES )); then
            tail -n "$LOG_MAX_LINES" "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
        fi
    fi
}

# ── Redis SET helper (non-fatal) ─────────────────────────────────────────
redis_set_last() {
    if command -v redis-cli &>/dev/null; then
        redis-cli SET "tx:cleanup:last" "$(date -Iseconds)" &>/dev/null || true
    fi
}

# ── Main ─────────────────────────────────────────────────────────────────
rotate_log

if [[ "$DRY_RUN" == true ]]; then
    log "=== tx-cleanup DRY-RUN started (no deletions) ==="
else
    log "=== tx-cleanup started ==="
fi

count_deleted=0
count_promoted=0
count_checked=0

# Safety: only .t-* pattern, maxdepth 1, must be directory
while IFS= read -r dir; do
    [[ -z "$dir" ]] && continue
    count_checked=$(( count_checked + 1 ))
    name=$(basename "$dir")

    # Guard: never touch non-.t-* names (belt-and-suspenders)
    if [[ "$name" != .t-* ]]; then
        log "SKIP (pattern mismatch): $dir"
        continue
    fi

    # Check for promoted flag
    meta_file="${dir}/.tx-meta.json"
    if [[ -f "$meta_file" ]]; then
        # Extract "promoted":true using grep (no jq dependency)
        if grep -q '"promoted"\s*:\s*true' "$meta_file" 2>/dev/null; then
            count_promoted=$(( count_promoted + 1 ))
            log "KEEP (promoted=true): $dir"
            continue
        fi
    fi

    # Delete or dry-report
    if [[ "$DRY_RUN" == true ]]; then
        log "DRY: would delete → $dir"
    else
        if rm -rf "$dir" 2>/dev/null; then
            count_deleted=$(( count_deleted + 1 ))
            log "DELETED: $dir"
        else
            log "ERROR: failed to delete $dir"
        fi
    fi

done < <(find "$PROJECTS_ROOT" -maxdepth 1 -type d -name '.t-*' -mtime +"$AGE_DAYS" 2>/dev/null)

# ── Summary ──────────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == true ]]; then
    log "=== DRY-RUN complete | checked=$count_checked promoted=$count_promoted would_delete=$count_deleted ==="
else
    log "=== Complete | checked=$count_checked deleted=$count_deleted promoted(kept)=$count_promoted ==="
    redis_set_last
fi

exit 0
