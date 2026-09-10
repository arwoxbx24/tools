#!/bin/bash
# ============================================================================
# git-maintenance-pm2.sh — Loop-based daemon for weekly git optimization
# SAFE for 8GB RAM server: no --aggressive, window=10, nice/ionice, memory cap
# Runs in infinite loop with 7-day sleep intervals (no PM2 cron-restart needed)
# PM2: pm2 start ecosystem.config.js --no-autorestart
# Created: 2026-02-07
# ============================================================================

set +e

# Memory safety
ulimit -v 524288  # 512MB virtual memory cap

# Run interval: weekly (604800 seconds = 7 days)
INTERVAL=604800

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/git-maintenance.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Limit git memory usage (safe for 8GB server with other processes)
export GIT_PACK_WINDOW_MEMORY=256m

# All git repos to maintain
REPOS=(
    "/root/claude-projects"
    "/root/claude-projects/claude-state"
    "/root/claude-projects/b24-arwox"
"/root/claude-projects/telegram-ai-bot"
    "/root/claude-projects/photo_downloader_dist"
    "/root/claude-projects/voice-transcriber"
    "/root/claude-projects/voiceflow-app"
    "/root/claude-projects/win10-assistant-setup"
    "/root/claude-projects/yubikey-v1"
    "/root/claude-projects/yubikey-v2"
    "/root/claude-projects/scripts_others"
)

while true; do
    log "=== GIT MAINTENANCE START ==="

    TOTAL_BEFORE=0
    TOTAL_AFTER=0

    for REPO in "${REPOS[@]}"; do
        if [ ! -d "$REPO/.git" ]; then
            continue
        fi

        cd "$REPO" || continue

        # Skip repos with .git < 50MB (not worth optimizing)
        GIT_SIZE=$(du -sm .git 2>/dev/null | cut -f1)
        if [ "${GIT_SIZE:-0}" -lt 50 ]; then
            log "  Skip $REPO (${GIT_SIZE}MB < 50MB threshold)"
            continue
        fi

        # Remove stale locks
        rm -f .git/index.lock .git/gc.pid 2>/dev/null

        # Size before
        SIZE_BEFORE=$(du -sm .git 2>/dev/null | cut -f1)
        TOTAL_BEFORE=$((TOTAL_BEFORE + SIZE_BEFORE))

        log "--- $REPO (${SIZE_BEFORE}MB) ---"

        # 1. Expire old reflog (keep 30 days)
        git reflog expire --expire=30.days --all 2>/dev/null

        # 2. Standard gc (NO --aggressive, safe for RAM)
        nice -n 19 ionice -c3 git gc --prune=now 2>&1 | tail -3 >> "$LOG_FILE"

        # 3. Light repack (window=10 = ~100MB RAM max)
        nice -n 19 ionice -c3 git repack -a -d --depth=50 --window=10 2>/dev/null

        # 4. Prune unreachable
        git prune --expire=now 2>/dev/null

        # 5. Prune stale remote branches
        git remote prune origin 2>/dev/null

        # Size after
        SIZE_AFTER=$(du -sm .git 2>/dev/null | cut -f1)
        TOTAL_AFTER=$((TOTAL_AFTER + SIZE_AFTER))
        SAVED=$((SIZE_BEFORE - SIZE_AFTER))

        log "  ${SIZE_BEFORE}MB -> ${SIZE_AFTER}MB (saved ${SAVED}MB)"

        # Pause 30s between repos to spread load
        sleep 30
    done

    TOTAL_SAVED=$((TOTAL_BEFORE - TOTAL_AFTER))
    log "=== COMPLETE: ${TOTAL_BEFORE}MB -> ${TOTAL_AFTER}MB (saved ${TOTAL_SAVED}MB) ==="

    log "Sleeping ${INTERVAL}s until next run..."
    sleep $INTERVAL
done
