#!/bin/bash
# tmux-claude-status.sh — Claude agent status for tmux statusbar
# Output: "🟢 N agents" or "⚪ idle"
# Fast: designed for tmux status-interval 1 — must complete <100ms

# ── 1. Agent count ─────────────────────────────────────────────────────────
AGENT_COUNT=$(pgrep -c -x "claude" 2>/dev/null || echo 0)
if [ "$AGENT_COUNT" -eq 0 ]; then
    AGENT_COUNT=$(pgrep -c -f '/bin/claude' 2>/dev/null || echo 0)
fi

# ── 2. Pipeline phase from /tmp/.claude-pipeline-phase ─────────────────────
PHASE_LABEL=""
NOW_PHASE=$(date +%s)
WINDOW_ID=$(tmux display-message -p '#{window_id}' 2>/dev/null || echo "w0")
PHASE_FILE="/tmp/.claude-pipeline-phase-${WINDOW_ID}"
[ ! -f "$PHASE_FILE" ] && PHASE_FILE="/tmp/.claude-pipeline-phase"

if [ -f "$PHASE_FILE" ]; then
    PHASE_MTIME=$(stat -c %Y "$PHASE_FILE" 2>/dev/null || echo 0)
    PHASE_AGE=$(( NOW_PHASE - PHASE_MTIME ))
    if [ "$PHASE_AGE" -le 600 ]; then
        PHASE_RAW=$(cat "$PHASE_FILE" 2>/dev/null | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
        case "$PHASE_RAW" in
            IDLE)   PHASE_LABEL="⚪" ;;
            AUDIT)  PHASE_LABEL="🔍AUDIT" ;;
            BRAIN)  PHASE_LABEL="🧠BRAIN" ;;
            PLAN)   PHASE_LABEL="📋PLAN" ;;
            EXEC)   PHASE_LABEL="⚡EXEC" ;;
            VERIFY) PHASE_LABEL="✅VERIFY" ;;
            WORK)   PHASE_LABEL="🔨WORK" ;;
            *)      PHASE_LABEL="⚪" ;;
        esac
    fi
fi

[ -z "$PHASE_LABEL" ] && PHASE_LABEL="⚪"

if [ "$PHASE_LABEL" = "⚪" ]; then
    PHASE_PREFIX=""
else
    PHASE_PREFIX="${PHASE_LABEL} "
fi

# ── 3. Compose output ──────────────────────────────────────────────────────
if [ "${AGENT_COUNT}" -gt 0 ] 2>/dev/null; then
    echo "${PHASE_PREFIX}#[fg=green]🟢#[default] ${AGENT_COUNT} agents"
else
    echo "#[fg=white]${PHASE_PREFIX}⚪ idle#[default]"
fi
