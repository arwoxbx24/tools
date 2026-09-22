#!/bin/bash
# tx-cleanup.sh — Remove stale temporary transaction projects (.t-*) older than 72h
# Skip directories where .tx-meta.json has "promoted":true
# Usage: tx-cleanup.sh [--dry]
# PM2: cron_restart "0 3 * * *", autorestart false
# Удаление передано стадии уборки с гейтом restic (US3, spec:055); здесь остаётся отметка tx:cleanup:last в redis.

set -uo pipefail

# ── Config ──────────────────────────────────────────────────────────────
LOG_FILE="/var/log/tx-cleanup.log"
LOG_MAX_LINES=1000
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
    log "=== tx-cleanup DRY-RUN (удаление передано стадии) ==="
else
    log "=== tx-cleanup started (удаление передано стадии, отметка tx:cleanup:last) ==="
    redis_set_last
fi

exit 0
