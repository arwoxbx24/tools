#!/bin/bash
# Delegate task to Alex account (acc2) first, fallback to internal
# Usage: bash delegate-task.sh "task description" [model: sonnet|haiku]

set -e

TASK="$1"
MODEL="${2:-sonnet}"
ALEX_CONFIG="/root/.claude_alex_acc2"
EXPERT_CONFIG="/root/workspaces/tools/acc1-scripts"
LOG_FILE="$EXPERT_CONFIG/logs/delegation.log"
STATUS_FILE="$EXPERT_CONFIG/data/delegation-status.json"

mkdir -p "$(dirname "$LOG_FILE")" "$(dirname "$STATUS_FILE")"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# MANDATORY: Get session context from Redis before ANY work
get_session_context() {
    local SESSION_KEY=$(redis-cli GET session:latest 2>/dev/null)
    if [ -n "$SESSION_KEY" ]; then
        REDIS_CONTEXT=$(redis-cli HGETALL "$SESSION_KEY" 2>/dev/null | paste - - | tr '\t' '=' | tr '\n' ';')
        log "REDIS_CONTEXT: $REDIS_CONTEXT"
        export REDIS_SESSION_CONTEXT="$REDIS_CONTEXT"
    fi
}

# Build context prefix for agent task
build_context_prefix() {
    local PREFIX="## Session Context (from Redis)\n"
    PREFIX+="Before starting: restore context from Redis.\n"
    PREFIX+="\`\`\`bash\nredis-cli HGETALL \"\$(redis-cli GET session:latest)\"\n\`\`\`\n\n"
    PREFIX+="## Priority Order\n"
    PREFIX+="1. Redis session → restore context\n"
    PREFIX+="2. Local plans → check /root/workspaces/tools/acc1-scripts/plans/\n"
    PREFIX+="3. GitHub issues → check open issues\n\n"
    PREFIX+="## Task\n"
    echo -e "$PREFIX"
}

# Check if Alex account has capacity
check_alex_capacity() {
    # Try a simple command on Alex account
    CLAUDE_CONFIG_DIR="$ALEX_CONFIG" timeout 10 claude --version >/dev/null 2>&1
    return $?
}

# Execute task on Alex account
run_on_alex() {
    # CLEAR TERMINAL OUTPUT - показываем модель явно
    echo ""
    echo "========================================="
    echo "🚀 DELEGATING TO: ALEX (acc2)"
    echo "📦 MODEL: $MODEL"
    echo "📋 TASK: ${TASK:0:80}..."
    echo "========================================="
    echo ""

    log "DELEGATE: Running on Alex (acc2) with model=$MODEL"
    log "TASK: $TASK"

    # MANDATORY: Get Redis context first
    get_session_context

    # Build task with context prefix
    CONTEXT_PREFIX=$(build_context_prefix)
    FULL_TASK="${CONTEXT_PREFIX}${TASK}"

    # Set git identity for Alex account
    if [ -f "/root/.claude_expert_acc2/scripts/git-identity.sh" ]; then
        source /root/.claude_expert_acc2/scripts/git-identity.sh
    fi

    # Run claude with Alex config (task includes Redis context instructions)
    RESULT=$(CLAUDE_CONFIG_DIR="$ALEX_CONFIG" GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Claude ALEX}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-alex@arwox.ru}" GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-Claude ALEX}" GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-alex@arwox.ru}" claude -p "$FULL_TASK" --model "$MODEL" --dangerously-skip-permissions 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log "SUCCESS: Task completed on Alex account"
        echo "$RESULT"
        return 0
    else
        # Check if rate limited
        if echo "$RESULT" | grep -qi "rate.limit\|too.many.requests\|429\|hit.your.limit"; then
            log "⚠️ RATE_LIMIT: Alex account hit limit, falling back to Expert"
            echo "⚠️ ALEX LIMIT REACHED - Switching to Expert/CODEX" >&2
            # Create flag file for monitoring
            echo "$(date -Iseconds)|alex|rate_limit|$TASK" >> "$EXPERT_CONFIG/data/agent-limits.log"
            return 1
        else
            log "ERROR: Task failed on Alex: $RESULT"
            return 2
        fi
    fi
}

# Execute task on Expert account (fallback)
run_on_expert() {
    # CLEAR TERMINAL OUTPUT - fallback
    echo ""
    echo "========================================="
    echo "⚠️  FALLBACK TO: EXPERT (acc1)"
    echo "📦 MODEL: $MODEL"
    echo "📋 TASK: ${TASK:0:80}..."
    echo "========================================="
    echo ""

    log "FALLBACK: Running on Expert (acc1) with model=$MODEL"

    # MANDATORY: Get Redis context first
    get_session_context

    # Build task with context prefix
    CONTEXT_PREFIX=$(build_context_prefix)
    FULL_TASK="${CONTEXT_PREFIX}${TASK}"

    # Set git identity for Expert account
    source "$EXPERT_CONFIG/scripts/git-identity.sh" 2>/dev/null || true

    RESULT=$(CLAUDE_CONFIG_DIR="$EXPERT_CONFIG" GIT_AUTHOR_NAME="${GIT_AUTHOR_NAME:-Claude Expert}" GIT_AUTHOR_EMAIL="${GIT_AUTHOR_EMAIL:-expert@arwox.ru}" GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-Claude Expert}" GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-expert@arwox.ru}" claude -p "$FULL_TASK" --model "$MODEL" --dangerously-skip-permissions 2>&1)
    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log "SUCCESS: Task completed on Expert account (fallback)"
        echo "$RESULT"
        return 0
    else
        log "ERROR: Task failed on Expert: $RESULT"
        return 1
    fi
}

# Update status file
update_status() {
    local account="$1"
    local status="$2"

    cat > "$STATUS_FILE" << EOF
{
    "last_delegation": "$(date -Iseconds)",
    "last_account": "$account",
    "last_status": "$status",
    "task_preview": "${TASK:0:100}"
}
EOF
}

# Main logic
if [ -z "$TASK" ]; then
    echo "Usage: bash delegate-task.sh \"task description\" [model: sonnet|haiku]"
    exit 1
fi

log "========================================="
log "DELEGATION START"

if check_alex_capacity; then
    if run_on_alex; then
        update_status "alex" "success"
        exit 0
    else
        # Rate limited or error, try Expert
        if run_on_expert; then
            update_status "expert" "fallback_success"
            exit 0
        else
            update_status "expert" "failed"
            exit 1
        fi
    fi
else
    log "WARNING: Alex account not available, using Expert directly"
    if run_on_expert; then
        update_status "expert" "direct_success"
        exit 0
    else
        update_status "expert" "failed"
        exit 1
    fi
fi
