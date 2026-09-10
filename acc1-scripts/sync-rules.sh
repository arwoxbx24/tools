#!/bin/bash
# Sync rules between acc1 and acc2
# Runs every 10 minutes via scheduler

set -euo pipefail

ACC1="/root/workspaces/tools/acc1-scripts"
ACC2="/root/.claude_alex_acc2"
LOG="$ACC1/logs/sync-rules.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# Sync CLAUDE.md (acc1 is master)
if [ -f "$ACC1/CLAUDE.md" ]; then
    if ! diff -q "$ACC1/CLAUDE.md" "$ACC2/CLAUDE.md" >/dev/null 2>&1; then
        cp "$ACC1/CLAUDE.md" "$ACC2/CLAUDE.md"
        log "Synced CLAUDE.md to acc2"
    fi
fi

# Sync hooks (acc1 is master)
for hook in security-guard.sh enforce-github-issue.sh; do
    if [ -f "$ACC1/hooks/$hook" ]; then
        if ! diff -q "$ACC1/hooks/$hook" "$ACC2/hooks/$hook" >/dev/null 2>&1; then
            cp "$ACC1/hooks/$hook" "$ACC2/hooks/$hook"
            chmod +x "$ACC2/hooks/$hook"
            log "Synced $hook to acc2"
        fi
    fi
done

# Sync active-issue (bidirectional - use newest)
if [ -f "$ACC1/data/active-issue.txt" ] && [ -f "$ACC2/data/active-issue.txt" ]; then
    if [ "$ACC1/data/active-issue.txt" -nt "$ACC2/data/active-issue.txt" ]; then
        cp "$ACC1/data/active-issue.txt" "$ACC2/data/active-issue.txt"
    elif [ "$ACC2/data/active-issue.txt" -nt "$ACC1/data/active-issue.txt" ]; then
        cp "$ACC2/data/active-issue.txt" "$ACC1/data/active-issue.txt"
    fi
fi

log "Sync complete"
