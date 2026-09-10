#!/bin/bash
# V213: Switch project lock
# Usage: switch-project.sh <project-name>
# Agent calls this when user explicitly asks to work in a different project
# The hook whitelists this script — it's the ONLY allowed way to switch

# Detect session ID: prefer $2 arg, then CLAUDE_SESSION_ID env, then fallback
if [[ -n "$2" ]]; then
    SESSION_ID="$2"
elif [[ -n "$CLAUDE_SESSION_ID" ]]; then
    SESSION_ID="$CLAUDE_SESSION_ID"
else
    # Fallback: find most recent session (imprecise for parallel sessions)
    PROJECTS_DIR="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects"
    SESSION_ID=""
    if [ -d "$PROJECTS_DIR" ]; then
        SESSION_ID=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.jsonl$//')
    fi
fi
SESSION_ID="${SESSION_ID:-default}"
LOCK_FILE="/tmp/.project-dir-lock-${SESSION_ID}"
BASE="/root/claude-projects"

NEW_PROJECT="$1"

if [[ -z "$NEW_PROJECT" ]]; then
    echo "Usage: switch-project.sh <project-name>" >&2
    echo "Example: switch-project.sh hr-qualification-bot" >&2
    exit 1
fi

# Validate project directory exists
if [[ ! -d "$BASE/$NEW_PROJECT" ]]; then
    echo "ERROR: Project directory $BASE/$NEW_PROJECT does not exist!" >&2
    echo "Available projects:" >&2
    ls -1 "$BASE/" | grep -v '^\.' | head -20 >&2
    exit 1
fi

OLD_PROJECT=""
if [[ -f "$LOCK_FILE" ]]; then
    OLD_PROJECT=$(cat "$LOCK_FILE" 2>/dev/null)
fi

# Write /tmp lock file — hook expects FULL absolute path (checked at line 155 of project-directory-lock.sh)
echo "$BASE/$NEW_PROJECT" > "$LOCK_FILE"

# [STICKY-WRITER-DISABLED 2026-04-14] CEO: one source of truth = CWD.
# Redis sticky session:sticky:project:* removed — lock file (/tmp) is the only project state.
# if command -v redis-cli &>/dev/null; then
#     REDIS_KEY="session:sticky:project:${SESSION_ID}"
#     redis-cli SET "$REDIS_KEY" "$NEW_PROJECT" EX 86400 >/dev/null 2>&1 \
#         && echo "[V213] Redis sticky set: $REDIS_KEY = $NEW_PROJECT" >&2 \
#         || echo "[V213] WARN: Redis write failed for $REDIS_KEY" >&2
# fi

if [[ -n "$OLD_PROJECT" && "$OLD_PROJECT" != "$NEW_PROJECT" ]]; then
    echo "[V213] Project switched: $OLD_PROJECT → $NEW_PROJECT" >&2
else
    echo "[V213] Project locked: $NEW_PROJECT" >&2
fi

echo "Switched: $NEW_PROJECT"
exit 0
