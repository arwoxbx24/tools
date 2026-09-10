#!/bin/bash
set +e
STATE_DIR="/root/workspaces/tools/acc1-scripts/state"
BASE="/root/claude-projects"
mkdir -p "$STATE_DIR"

# Get session ID from environment (set by universal-project-router.sh)
SESSION_ID="${CLAUDE_SESSION_ID:-}"

# Priority 1: explicit switch via /p command
EXPLICIT=$(cat "$STATE_DIR/project-explicit" 2>/dev/null)
if [ -n "$EXPLICIT" ] && [ -d "$BASE/$EXPLICIT" ]; then
    echo "$EXPLICIT"
    exit 0
fi

# Priority 2: CWD — extract first dir component under /root/claude-projects/
CWD="${CLAUDE_CWD:-${PWD:-$BASE}}"
if [[ "$CWD" == "$BASE"/* ]]; then
    REL="${CWD#$BASE/}"
    PROJECT_DIR="${REL%%/*}"
    if [ -n "$PROJECT_DIR" ] && [ -d "$BASE/$PROJECT_DIR" ]; then
        echo "$PROJECT_DIR"
        # Session-scoped only — no global write to prevent cross-session pollution
        if [ -n "$SESSION_ID" ]; then
            redis-cli SET "session:sticky:${SESSION_ID}" "$PROJECT_DIR" EX 28800 &>/dev/null
        fi
        exit 0
    fi
fi

# Priority 3: TMUX pane-scoped sticky (file) — per-pane isolation when TMUX_PANE is set
if [ -n "${TMUX_PANE:-}" ]; then
    _PANE_CLEAN="${TMUX_PANE#%}"
    PANE_STICKY=$(cat "$STATE_DIR/project-sticky-${_PANE_CLEAN}" 2>/dev/null)
    if [ -n "$PANE_STICKY" ] && [ -d "$BASE/$PANE_STICKY" ]; then
        echo "$PANE_STICKY"
        exit 0
    fi
fi

# Priority 4: session-scoped sticky (Redis) — per-session, no cross-session pollution
if [ -n "$SESSION_ID" ]; then
    SESSION_STICKY=$(redis-cli GET "session:sticky:${SESSION_ID}" 2>/dev/null)
    if [ -n "$SESSION_STICKY" ] && [ "$SESSION_STICKY" != "(nil)" ] && [ -d "$BASE/$SESSION_STICKY" ]; then
        echo "$SESSION_STICKY"
        exit 0
    fi
fi

# Priority 5: global fallback REMOVED (cross-session pollution — see consolidated-session-isolation-arch.md FIX-2)

echo "none"
