#!/bin/bash
# ============================================================================
# git-maintenance.sh — Weekly git repository optimization
# Cron: 0 4 * * 0 /bin/bash /root/workspaces/tools/acc1-scripts/scripts/git-maintenance.sh
# Created: 2026-02-07
# ============================================================================

set +e

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/git-maintenance.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

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

log "=== GIT MAINTENANCE START ==="

TOTAL_BEFORE=0
TOTAL_AFTER=0

for REPO in "${REPOS[@]}"; do
    if [ ! -d "$REPO/.git" ]; then
        continue
    fi

    cd "$REPO"

    # Size before
    SIZE_BEFORE=$(du -sm .git 2>/dev/null | cut -f1)
    TOTAL_BEFORE=$((TOTAL_BEFORE + SIZE_BEFORE))

    log "--- $REPO (${SIZE_BEFORE}MB) ---"

    # 1. Expire reflog (remove old references)
    git reflog expire --expire=30.days --all 2>/dev/null

    # 2. Remove unreachable objects
    git prune --expire=now 2>/dev/null

    # 3. Garbage collection with aggressive packing
    git gc --aggressive --prune=now 2>&1 | tail -3 >> "$LOG_FILE"

    # 4. Repack for maximum compression
    git repack -a -d -f --depth=50 --window=50 2>/dev/null

    # 5. Remove stale remote tracking branches
    git remote prune origin 2>/dev/null

    # 6. Remove orphan lock files
    rm -f .git/index.lock .git/gc.pid 2>/dev/null

    # Size after
    SIZE_AFTER=$(du -sm .git 2>/dev/null | cut -f1)
    TOTAL_AFTER=$((TOTAL_AFTER + SIZE_AFTER))
    SAVED=$((SIZE_BEFORE - SIZE_AFTER))

    log "  ${SIZE_BEFORE}MB -> ${SIZE_AFTER}MB (saved ${SAVED}MB)"
done

TOTAL_SAVED=$((TOTAL_BEFORE - TOTAL_AFTER))
log "=== COMPLETE: ${TOTAL_BEFORE}MB -> ${TOTAL_AFTER}MB (saved ${TOTAL_SAVED}MB) ==="

exit 0
