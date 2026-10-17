#!/bin/bash
# Delegate task to OpenAI Codex (GPT-5.2) with fallback to Claude
# Usage: bash delegate-to-codex.sh "task description" [workdir]
#
# Priority:
# 1. Codex (GPT-5.2) - primary
# 2. Claude (Expert internal) - fallback on error/limit

set -e

TASK="$1"
WORKDIR="${2:-/root/claude-projects}"
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/codex-delegation.log"
STATUS_FILE="/root/workspaces/tools/acc1-scripts/data/codex-delegation-status.json"
TIMEOUT=300  # 5 minutes max

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATUS_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

update_status() {
    local agent="$1"
    local status="$2"
    cat > "$STATUS_FILE" << EOF
{
    "last_delegation": "$(date -Iseconds)",
    "last_agent": "$agent",
    "last_status": "$status",
    "task_preview": "${TASK:0:100}"
}
EOF
}

# Fallback to Claude Expert internal agent
run_on_claude_internal() {
    log "FALLBACK: Running on Claude Expert (internal sonnet agent)"

    # Use claude CLI with internal prompt
    RESULT=$(echo "refused: Claude runs only via /root/workspaces/tools/bin/sdk-agent (owner 17.10, dcfg-l5wpm)" >&2; exit 3) || {
        EXIT_CODE=$?
        log "ERROR: Claude internal also failed with exit code $EXIT_CODE"
        update_status "claude_internal" "failed"
        echo "$RESULT"
        return $EXIT_CODE
    }

    log "SUCCESS: Task completed on Claude internal (fallback)"
    update_status "claude_internal" "fallback_success"
    echo "$RESULT"
    return 0
}

# Primary: Run on Codex
run_on_codex() {
    log "PRIMARY: Running on Codex (GPT-5.2)"

    START_TIME=$(date +%s)

    RESULT=$(timeout $TIMEOUT codex exec --skip-git-repo-check "$TASK" 2>&1)
    EXIT_CODE=$?

    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))

    if [ $EXIT_CODE -eq 0 ]; then
        # Extract token usage
        TOKENS=$(echo "$RESULT" | grep -oP 'tokens used\n\K[0-9,]+' | tr -d ',' | tail -1 2>/dev/null || echo "0")
        log "SUCCESS: Completed in ${DURATION}s, tokens: $TOKENS"
        update_status "codex" "success"
        echo "$RESULT" | head -n -10
        return 0
    fi

    # Check error type
    if [ $EXIT_CODE -eq 124 ]; then
        log "TIMEOUT: Codex timed out after ${TIMEOUT}s"
    elif echo "$RESULT" | grep -qi "rate.limit\|too.many.requests\|429\|quota"; then
        log "RATE_LIMIT: Codex hit rate limit"
    else
        log "ERROR: Codex failed with exit code $EXIT_CODE"
    fi

    return 1
}

# Main
if [ -z "$TASK" ]; then
    echo "Usage: bash delegate-to-codex.sh \"task description\" [workdir]"
    exit 1
fi

log "========================================="
log "CODEX DELEGATION START"
log "TASK: ${TASK:0:100}..."
log "WORKDIR: $WORKDIR"

# Check if codex is available
if ! command -v codex &> /dev/null; then
    log "WARNING: codex CLI not found, using Claude internal directly"
    if run_on_claude_internal; then
        exit 0
    else
        exit 1
    fi
fi

# Try Codex first, fallback to Claude on failure
if run_on_codex; then
    log "========================================="
    exit 0
else
    log "Codex failed, falling back to Claude internal..."
    if run_on_claude_internal; then
        log "========================================="
        exit 0
    else
        log "========================================="
        exit 1
    fi
fi
