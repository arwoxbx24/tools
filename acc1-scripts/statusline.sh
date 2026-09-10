#!/bin/bash
# Claude Code statusLine script
# Shows: user@host / project / Model / ctx%
# Format: root@server / stroyremont / Sonnet 4.6 / 15% ctx
# Reads V213 lock file for authoritative project directory

set +e

# Read JSON input from Claude Code
input=$(cat)

# Extract session_id for scoping
SESSION_ID=$(echo "$input" | jq -r '.session_id // empty' 2>/dev/null)
[ -z "$SESSION_ID" ] && SESSION_ID="unknown"

# Get project name from V213 lock file (authoritative source, per-session)
# SESSION_ID already extracted from JSON input above (line 13)
LOCK_FILE="/tmp/.project-dir-lock-${SESSION_ID}"
if [[ -f "$LOCK_FILE" ]] && [[ -s "$LOCK_FILE" ]]; then
    PROJECT_NAME=$(cat "$LOCK_FILE" 2>/dev/null)
else
    # Fallback to workspace.project_dir from Claude Code JSON
    DISPLAY_DIR=$(echo "$input" | jq -r '.cwd // .workspace.project_dir // empty' 2>/dev/null)
    if [[ -z "$DISPLAY_DIR" ]]; then
        DISPLAY_DIR="$(pwd)"
    fi
    # If path contains /clients/ — show full relative path from claude-projects root
    if [[ "$DISPLAY_DIR" == */claude-projects/clients/* ]]; then
        PROJECT_NAME="${DISPLAY_DIR#*/claude-projects/}"
    else
        # Extract just the basename
        PROJECT_NAME=$(basename "$DISPLAY_DIR")
    fi
fi

# Get model info if available
MODEL=$(echo "$input" | jq -r '.model.display_name // empty' 2>/dev/null)

# Get context window usage if available
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
if [[ -n "$PCT" ]] && [[ "$PCT" != "null" ]]; then
    PCT=$(echo "$PCT" | cut -d. -f1)
else
    PCT=""
fi

# Color definitions
GREEN="\033[01;32m"
BLUE="\033[01;34m"
YELLOW="\033[33m"
DIM="\033[90m"
RESET="\033[00m"
SEP="${DIM} / ${RESET}"

# Build status line
_HOST_FULL=$(hostname -s)
_HOST_SHORT="${_HOST_FULL#*-}"
USER_HOST="${GREEN}$(whoami)@${_HOST_SHORT}${RESET}"
PROJECT_PART="${BLUE}${PROJECT_NAME}${RESET}"

STATUS="${USER_HOST}${SEP}${PROJECT_PART}"

if [[ -n "$MODEL" ]] && [[ "$MODEL" != "null" ]]; then
    # Compact model name: "Claude Opus 4.6 (1M context)" → "Opus4.6·1M"
    MODEL_COMPACT=$(echo "$MODEL" | sed \
        -e 's/^Claude //' \
        -e 's/ (\([0-9]*[KkMm]\) context)/·\1/' \
        -e 's/ \([0-9]\)/\1/')
    STATUS="${STATUS}${SEP}${YELLOW}${MODEL_COMPACT}${RESET}"
fi

if [[ -n "$PCT" ]] && [[ "$PCT" != "0" ]]; then
    STATUS="${STATUS}${SEP}${PCT}%"
fi

# Rate limits: show warning if usage is high
RATE_5H=$(echo "$input" | jq -r '.rate_limits["5h"].used_percentage // empty' 2>/dev/null)
RATE_7D=$(echo "$input" | jq -r '.rate_limits["7d"].used_percentage // empty' 2>/dev/null)

if [[ -n "$RATE_5H" ]] && [[ "$RATE_5H" != "null" ]]; then
    RATE_5H_INT=$(echo "$RATE_5H" | cut -d. -f1)
    if (( RATE_5H_INT > 90 )); then
        STATUS="${STATUS}${SEP}🔴${RATE_5H_INT}%"
    elif (( RATE_5H_INT > 70 )); then
        STATUS="${STATUS}${SEP}⚡${RATE_5H_INT}%"
    fi
fi

if [[ -n "$RATE_7D" ]] && [[ "$RATE_7D" != "null" ]]; then
    RATE_7D_INT=$(echo "$RATE_7D" | cut -d. -f1)
    if (( RATE_7D_INT > 50 )); then
        STATUS="${STATUS}${SEP}📅${RATE_7D_INT}%7d"
    fi
fi

# Agent counter: count only THIS session's active agent markers (<5 min old)
# Cleanup stale markers (>10 min) globally
AGENT_COUNT=0
NOW=$(date +%s)
for f in /tmp/.agent-visual-*; do
    [[ -f "$f" ]] || continue
    MTIME=$(stat -c %Y "$f" 2>/dev/null || echo 0)
    AGE=$(( NOW - MTIME ))
    if (( AGE > 600 )); then
        rm -f "$f" 2>/dev/null
    elif (( AGE < 300 )); then
        # Only count markers for THIS session (filename contains session_id)
        BASENAME=$(basename "$f")
        if [[ "$BASENAME" == *"${SESSION_ID}"* ]]; then
            (( AGENT_COUNT++ ))
        fi
    fi
done

if (( AGENT_COUNT > 0 )); then
    if (( AGENT_COUNT == 1 )); then
        AGENT_LABEL="агент"
    elif (( AGENT_COUNT <= 4 )); then
        AGENT_LABEL="агента"
    else
        AGENT_LABEL="агентов"
    fi
    STATUS="${STATUS}${SEP}🟡 ${AGENT_COUNT} ${AGENT_LABEL}"
fi

# Task counters: Redis first, fallback to /tmp/.task-current-{SESSION_ID}
TASK_COMPLETED=0
TASK_IN_PROGRESS=0
TASK_PENDING=0
CURRENT_TASK=""

if command -v redis-cli &>/dev/null; then
    REDIS_RAW=$(redis-cli --no-auth-warning GET "context:active_tasks:${SESSION_ID}" 2>/dev/null)
    if [[ -n "$REDIS_RAW" ]] && [[ "$REDIS_RAW" != "(nil)" ]]; then
        TASK_COMPLETED=$(echo "$REDIS_RAW" | jq '[.[] | select(.status=="completed")] | length' 2>/dev/null || echo 0)
        TASK_IN_PROGRESS=$(echo "$REDIS_RAW" | jq '[.[] | select(.status=="in_progress")] | length' 2>/dev/null || echo 0)
        TASK_PENDING=$(echo "$REDIS_RAW" | jq '[.[] | select(.status=="pending")] | length' 2>/dev/null || echo 0)
        CURRENT_TASK=$(echo "$REDIS_RAW" | jq -r '[.[] | select(.status=="in_progress")][0].title // empty' 2>/dev/null)
    fi
fi

TASK_FILE="/tmp/.task-current-${SESSION_ID}"
if [[ -z "$CURRENT_TASK" ]] && [[ -f "$TASK_FILE" ]] && [[ -s "$TASK_FILE" ]]; then
    CURRENT_TASK=$(cat "$TASK_FILE" 2>/dev/null)
    if [[ -n "$CURRENT_TASK" ]] && (( TASK_IN_PROGRESS == 0 )); then
        TASK_IN_PROGRESS=1
    fi
fi

TASK_TOTAL=$(( TASK_COMPLETED + TASK_IN_PROGRESS + TASK_PENDING ))
if (( TASK_TOTAL > 0 )); then
    TASK_SEG=""
    (( TASK_COMPLETED > 0 )) && TASK_SEG="${TASK_SEG}✅${TASK_COMPLETED}"
    if (( TASK_IN_PROGRESS > 0 )); then
        [[ -n "$TASK_SEG" ]] && TASK_SEG="${TASK_SEG} "
        TASK_SEG="${TASK_SEG}⏳${TASK_IN_PROGRESS}"
    fi
    if (( TASK_PENDING > 0 )); then
        [[ -n "$TASK_SEG" ]] && TASK_SEG="${TASK_SEG} "
        TASK_SEG="${TASK_SEG}📋${TASK_PENDING}"
    fi
    STATUS="${STATUS}${SEP}${TASK_SEG} задач"
fi

if [[ -n "$CURRENT_TASK" ]]; then
    SHORT_TASK="${CURRENT_TASK:0:30}"
    [[ "${#CURRENT_TASK}" -gt 30 ]] && SHORT_TASK="${SHORT_TASK}…"
    STATUS="${STATUS}${SEP}${DIM}${SHORT_TASK}${RESET}"
fi

# Active tasks: in_progress + pending (computed above)
ACTIVE_TASK_COUNT=$(( TASK_IN_PROGRESS + TASK_PENDING ))
if (( ACTIVE_TASK_COUNT == 0 )); then
    ACTIVE_TASK_COUNT=$(ls /tmp/.task-current-* 2>/dev/null | wc -l)
fi
if (( ACTIVE_TASK_COUNT > 0 )); then
    STATUS="${STATUS}${SEP}${DIM}${ACTIVE_TASK_COUNT}tasks${RESET}"
fi

# Timeweb AI usage
TW_COUNT=$(redis-cli GET "v395:tw-calls:${SESSION_ID}" 2>/dev/null || echo "0")
TW_COUNT=${TW_COUNT:-0}
if [[ "$TW_COUNT" -gt 0 ]] 2>/dev/null; then
    STATUS="${STATUS}${SEP}${YELLOW}🤖${TW_COUNT}tw${RESET}"
fi

# Session uptime: age of session marker file
UPTIME_STR=""
SESSION_FILE="/tmp/.claude-session-${SESSION_ID}"
if [[ ! -f "$SESSION_FILE" ]]; then
    SESSION_FILE=$(ls /tmp/.claude-session-* 2>/dev/null | head -1)
fi
if [[ -n "$SESSION_FILE" ]] && [[ -f "$SESSION_FILE" ]]; then
    SMTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo 0)
    SNOW=$(date +%s)
    SAGE=$(( SNOW - SMTIME ))
    if (( SAGE > 0 )); then
        if (( SAGE < 3600 )); then
            UPTIME_STR="$(( SAGE / 60 ))m"
        elif (( SAGE < 86400 )); then
            UPTIME_STR="$(( SAGE / 3600 ))h$(( (SAGE % 3600) / 60 ))m"
        else
            UPTIME_STR="$(( SAGE / 86400 ))d$(( (SAGE % 86400) / 3600 ))h"
        fi
    fi
fi
if [[ -n "$UPTIME_STR" ]]; then
    STATUS="${STATUS}${SEP}${DIM}${UPTIME_STR}${RESET}"
fi

printf "%b\n" "${STATUS}"
