#!/bin/bash
# cleanup-agent-downloads.sh — PM2 hourly cleanup of agent download directories
# Cleans .claude-downloads/ in all projects + /tmp/claude-* and /tmp/test-*
# Safety: only cleans directories with .claude-marker file
set -euo pipefail

LOG="/tmp/cleanup-agent-downloads.log"
PROJECTS_DIR="/root/claude-projects"
MAX_AGE_DAYS=7  # 7 days

echo "$(date '+%Y-%m-%d %H:%M:%S') — Cleanup started" >> "$LOG"

CLEANED=0
SKIPPED=0

# Clean .claude-downloads/ in project directories
if [ -d "$PROJECTS_DIR" ]; then
    for dl_dir in "$PROJECTS_DIR"/*/.claude-downloads; do
        [ -d "$dl_dir" ] || continue

        # Safety: only clean if marker exists
        if [ ! -f "$dl_dir/.claude-marker" ]; then
            echo "  SKIP (no marker): $dl_dir" >> "$LOG"
            SKIPPED=$((SKIPPED + 1))
            continue
        fi

        # Delete files older than 24h (except marker)
        while IFS= read -r -d '' file; do
            [ -z "$file" ] && continue
            rm -f "$file" 2>/dev/null && CLEANED=$((CLEANED + 1))
        done < <(find "$dl_dir" -maxdepth 2 -type f -mtime +"$MAX_AGE_DAYS" -not -name ".claude-marker" -print0 2>/dev/null)

        # Clean empty subdirectories (but not the dir itself)
        find "$dl_dir" -mindepth 1 -type d -empty -delete 2>/dev/null || true
    done
fi

# Clean /tmp/claude-* directories older than 24h
while IFS= read -r -d '' tmpdir; do
    [ -z "$tmpdir" ] && continue
    rm -rf "$tmpdir" 2>/dev/null && CLEANED=$((CLEANED + 1))
done < <(find /tmp -maxdepth 1 -name "claude-*" -type d -mtime +"$MAX_AGE_DAYS" -print0 2>/dev/null)

# Clean /tmp/test-* files older than 24h
while IFS= read -r -d '' tmpfile; do
    [ -z "$tmpfile" ] && continue
    rm -f "$tmpfile" 2>/dev/null && CLEANED=$((CLEANED + 1))
done < <(find /tmp -maxdepth 1 -name "test-*" -mtime +"$MAX_AGE_DAYS" -print0 2>/dev/null)

# Clean /tmp/claude-gdrive/ (legacy location) older than 24h
if [ -d "/tmp/claude-gdrive" ]; then
    while IFS= read -r -d '' file; do
        [ -z "$file" ] && continue
        rm -f "$file" 2>/dev/null && CLEANED=$((CLEANED + 1))
    done < <(find /tmp/claude-gdrive -type f -mtime +"$MAX_AGE_DAYS" -print0 2>/dev/null)
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') — Cleanup done: $CLEANED removed, $SKIPPED skipped" >> "$LOG"

# Trim log to last 100 lines
if [ -f "$LOG" ]; then
    tail -100 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
