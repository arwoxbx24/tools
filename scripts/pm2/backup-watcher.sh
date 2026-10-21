#!/bin/bash
# backup-watcher.sh — Watches profile tree and key project dirs for backup files
# Catches: *.backup, *.bak, *.backup.*, *.bak-*
# Runs as PM2 daemon, uses inotifywait -r for RECURSIVE monitoring
# v2: scoped dirs only, heavy project dirs excluded
# Удаление копий старше 5 суток передано стадии уборки с гейтом restic (US3, spec:055); сбор *.bak* остаётся.
set +e

PROFILE_DIR="/root/workspaces/system/tools/scripts"
BACKUP_DIR="${PROFILE_DIR}/backups"
LOG_FILE="/tmp/backup-watcher.log"
FIFO=""

mkdir -p "$BACKUP_DIR"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') — $1" >> "$LOG_FILE"
    if [ "$(wc -l < "$LOG_FILE" 2>/dev/null)" -gt 200 ]; then
        tail -100 "$LOG_FILE" > "${LOG_FILE}.tmp" && mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

INOTIFY_PID=""
# Kill tracked inotifywait on exit so no orphan tree survives a restart
FIFO="$(mktemp -u)"
mkfifo "$FIFO"
trap 'kill $INOTIFY_PID 2>/dev/null; rm -f "$FIFO"' EXIT TERM INT

move_all_backups() {
    local moved=0
    while IFS= read -r f; do
        [ -f "$f" ] || continue
        rel=$(echo "$f" | sed "s|^/root/||" | sed "s|/|__|g")
        mv "$f" "${BACKUP_DIR}/${rel}" 2>/dev/null && moved=$((moved + 1))
    done < <(find /root/ -maxdepth 5 \( -name "*.backup" -o -name "*.bak" -o -name "*.backup.*" -o -name "*.backup-*" -o -name "*.bak-*" -o -name "*.bak.*" \) -not -path "*/backups/*" -not -path "*/.git/*" -not -path "*/node_modules/*" -not -path "*/.pm2/dump.pm2.bak" 2>/dev/null)
    [ $moved -gt 0 ] && log "Sweep: moved $moved backup files"
}

# Active project dirs to watch (lightweight, no large binary dirs)
# Excludes: bitrix(1.3G), stroyremont(434M), financial-model(231M), pdf-decoder(203M),
#           hiddify-manager(165M), minio-b244(158M), photo_downloader_dist(79M), games, kinopoisk
WATCH_DIRS=(
    "${PROFILE_DIR}"
    "/root/workspaces/projects/transcription-dev"
    "/root/workspaces/projects/clients"
    "/root/workspaces/projects/claude-state"
    "/root/workspaces/projects/arwox-biz"
    "/root/workspaces/projects/arwoxbx24-github"
)

# Initial full sweep
move_all_backups
log "Watcher started. Monitoring ${#WATCH_DIRS[@]} scoped dirs"

# Recursive watch on scoped dirs only — avoids 7000+ inotify watches on full /root/workspaces/projects/
# inotifywait runs in background with its real PID tracked (INOTIFY_PID); trap kills it on exit (no orphans)
# Inner loop: if inotifywait exits early (e.g. watched dir removed), restart without PM2 restart
while true; do
    inotifywait -m -r -q -e create -e moved_to \
        --exclude '/(backups|\.git|node_modules|\.pm2|\.npm|\.cache|\.cursor-server|\.claude-downloads|logs?|tmp|__pycache__|\.next|dist|build)/' \
        --format '%w%f' "${WATCH_DIRS[@]}" 2>/dev/null > "$FIFO" &
    INOTIFY_PID=$!
    cat "$FIFO" | while read -r filepath; do
        case "$(basename "$filepath")" in
            *.backup|*.bak|*.backup.*|*.backup-*|*.bak-*|*.bak.*)
                sleep 1
                if [ -f "$filepath" ]; then
                    rel=$(echo "$filepath" | sed "s|^/root/||" | sed "s|/|__|g")
                    mv "$filepath" "${BACKUP_DIR}/${rel}" 2>/dev/null
                    log "Instant move: $(basename "$filepath") from $(dirname "$filepath")"
                fi
                ;;
        esac
    done
    # We're here because inotifywait closed the fifo (EOF). Make sure it's dead
    # before relaunching so no copies pile up.
    kill "$INOTIFY_PID" 2>/dev/null
    wait "$INOTIFY_PID" 2>/dev/null
    log "inotifywait exited unexpectedly, restarting watch in 2s"
    sleep 2
done
