#!/bin/bash
# ============================================================================
# fsm-task.sh — FSM helper for task lifecycle management
# States: BACKLOG → VALIDATE → IN_PROGRESS → VERIFY → DONE | FIX_LOOP
# Storage: Redis Hash task:{id}:state + Stream task:stream:{project}
# ============================================================================
# Usage:
#   fsm_create   <task_id> <subject> [project]
#   fsm_transition <task_id> <new_state> [reason]
#   fsm_status   <task_id>
#   fsm_list     [project]
# ============================================================================

set +e

REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"
MAX_FIX_RETRIES=3
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/fsm-task.log"

mkdir -p "$(dirname "$LOG_FILE")"

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

_redis() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

_log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

_redis_ok() {
    # Returns 0 if Redis is reachable, 1 otherwise
    _redis PING | grep -q "PONG" && return 0 || return 1
}

# ---------------------------------------------------------------------------
# Valid transitions table
# FORMAT: "FROM:TO"
# ---------------------------------------------------------------------------
_valid_transition() {
    local from="$1" to="$2"
    case "${from}:${to}" in
        "BACKLOG:VALIDATE")      return 0 ;;
        "BACKLOG:IN_PROGRESS")   return 0 ;;  # fast-track skip validate
        "VALIDATE:IN_PROGRESS")  return 0 ;;
        "VALIDATE:BACKLOG")      return 0 ;;  # rejected back to backlog
        "IN_PROGRESS:VERIFY")    return 0 ;;
        "IN_PROGRESS:FIX_LOOP")  return 0 ;;
        "VERIFY:DONE")           return 0 ;;
        "VERIFY:FIX_LOOP")       return 0 ;;  # verification failed
        "FIX_LOOP:IN_PROGRESS")  return 0 ;;  # retry
        "FIX_LOOP:ESCALATE")     return 0 ;;  # max retries reached
        "ESCALATE:IN_PROGRESS")  return 0 ;;  # manually unblocked
        # Allow self-transition only for FIX_LOOP (counting retries)
        "FIX_LOOP:FIX_LOOP")     return 0 ;;
        *)                        return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# fsm_create <task_id> <subject> [project]
# ---------------------------------------------------------------------------
fsm_create() {
    local task_id="$1"
    local subject="$2"
    local project="${3:-default}"

    if [ -z "$task_id" ]; then
        echo "ERROR: task_id required" >&2
        return 1
    fi

    _redis_ok || { _log "WARN Redis down, fsm_create skipped for $task_id"; return 0; }

    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')

    # Hash: task:{id}:state
    _redis HSET "task:${task_id}:state" \
        state "BACKLOG" \
        subject "$subject" \
        project "$project" \
        fix_retries "0" \
        created_at "$ts" \
        updated_at "$ts" > /dev/null

    # TTL: 30 days
    _redis EXPIRE "task:${task_id}:state" 2592000 > /dev/null

    # Stream entry
    _redis XADD "task:stream:${project}" "*" \
        task_id "$task_id" \
        event "CREATED" \
        from "" \
        to "BACKLOG" \
        subject "$subject" \
        ts "$ts" > /dev/null

    _log "fsm_create task=$task_id project=$project subject='$subject'"
    return 0
}

# ---------------------------------------------------------------------------
# fsm_transition <task_id> <new_state> [reason]
# ---------------------------------------------------------------------------
fsm_transition() {
    local task_id="$1"
    local new_state="$2"
    local reason="${3:-}"

    if [ -z "$task_id" ] || [ -z "$new_state" ]; then
        echo "ERROR: task_id and new_state required" >&2
        return 1
    fi

    _redis_ok || { _log "WARN Redis down, fsm_transition skipped for $task_id→$new_state"; return 0; }

    # Get current state
    local current_state
    current_state=$(_redis HGET "task:${task_id}:state" state)

    if [ -z "$current_state" ]; then
        echo "ERROR: task $task_id not found in FSM" >&2
        _log "ERROR fsm_transition task=$task_id not found"
        return 1
    fi

    # Validate transition
    if ! _valid_transition "$current_state" "$new_state"; then
        echo "ERROR: Invalid transition ${current_state}→${new_state} for task $task_id" >&2
        _log "REJECT transition task=$task_id ${current_state}→${new_state} reason='$reason'"
        return 1
    fi

    local project
    project=$(_redis HGET "task:${task_id}:state" project)
    project="${project:-default}"

    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')

    # Handle FIX_LOOP retry counting
    local fix_retries
    fix_retries=$(_redis HGET "task:${task_id}:state" fix_retries)
    fix_retries="${fix_retries:-0}"

    if [ "$new_state" = "FIX_LOOP" ]; then
        fix_retries=$((fix_retries + 1))
        if [ "$fix_retries" -ge "$MAX_FIX_RETRIES" ]; then
            echo "WARN: MAX_FIX_RETRIES ($MAX_FIX_RETRIES) reached for $task_id — auto-escalating" >&2
            _log "ESCALATE task=$task_id fix_retries=$fix_retries"
            new_state="ESCALATE"
        fi
        _redis HSET "task:${task_id}:state" fix_retries "$fix_retries" > /dev/null
    fi

    # Update state
    _redis HSET "task:${task_id}:state" \
        state "$new_state" \
        updated_at "$ts" > /dev/null

    # Stream audit trail
    _redis XADD "task:stream:${project}" "*" \
        task_id "$task_id" \
        event "TRANSITION" \
        from "$current_state" \
        to "$new_state" \
        fix_retries "$fix_retries" \
        reason "$reason" \
        ts "$ts" > /dev/null

    _log "fsm_transition task=$task_id ${current_state}→${new_state} reason='$reason'"
    echo "OK: ${current_state}→${new_state}"
    return 0
}

# ---------------------------------------------------------------------------
# fsm_status <task_id>
# ---------------------------------------------------------------------------
fsm_status() {
    local task_id="$1"

    if [ -z "$task_id" ]; then
        echo "ERROR: task_id required" >&2
        return 1
    fi

    _redis_ok || { echo "ERROR: Redis unavailable"; return 1; }

    local state subject project fix_retries created_at updated_at
    state=$(_redis HGET "task:${task_id}:state" state)

    if [ -z "$state" ]; then
        echo "NOT_FOUND: task $task_id has no FSM record"
        return 1
    fi

    subject=$(_redis HGET "task:${task_id}:state" subject)
    project=$(_redis HGET "task:${task_id}:state" project)
    fix_retries=$(_redis HGET "task:${task_id}:state" fix_retries)
    created_at=$(_redis HGET "task:${task_id}:state" created_at)
    updated_at=$(_redis HGET "task:${task_id}:state" updated_at)

    cat <<EOF
Task:       $task_id
Subject:    $subject
State:      $state
Project:    $project
FixRetries: $fix_retries / $MAX_FIX_RETRIES
Created:    $created_at
Updated:    $updated_at
EOF
    return 0
}

# ---------------------------------------------------------------------------
# fsm_list [project]
# ---------------------------------------------------------------------------
fsm_list() {
    local project="${1:-}"

    _redis_ok || { echo "ERROR: Redis unavailable"; return 1; }

    # Get all task:*:state keys
    local keys
    keys=$(_redis KEYS "task:*:state")

    if [ -z "$keys" ]; then
        echo "No FSM tasks found"
        return 0
    fi

    printf "%-20s %-12s %-10s %-3s %s\n" "TASK_ID" "STATE" "PROJECT" "FIX" "SUBJECT"
    printf "%-20s %-12s %-10s %-3s %s\n" "--------------------" "------------" "----------" "---" "-------"

    while IFS= read -r key; do
        local tid
        tid=$(echo "$key" | sed 's/^task://;s/:state$//')
        local s p f subj
        s=$(_redis HGET "$key" state)
        p=$(_redis HGET "$key" project)
        f=$(_redis HGET "$key" fix_retries)
        subj=$(_redis HGET "$key" subject)

        # Filter by project if specified
        if [ -n "$project" ] && [ "$p" != "$project" ]; then
            continue
        fi

        printf "%-20s %-12s %-10s %-3s %s\n" "$tid" "${s:-?}" "${p:-?}" "${f:-0}" "${subj:0:40}"
    done <<< "$keys"

    return 0
}

# ---------------------------------------------------------------------------
# CLI dispatch
# ---------------------------------------------------------------------------
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    CMD="${1:-help}"
    shift || true

    case "$CMD" in
        create)     fsm_create "$@" ;;
        transition) fsm_transition "$@" ;;
        status)     fsm_status "$@" ;;
        list)       fsm_list "$@" ;;
        help|--help|-h)
            echo "Usage: fsm-task.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  create     <task_id> <subject> [project]"
            echo "  transition <task_id> <new_state> [reason]"
            echo "  status     <task_id>"
            echo "  list       [project]"
            echo ""
            echo "States: BACKLOG → VALIDATE → IN_PROGRESS → VERIFY → DONE | FIX_LOOP → ESCALATE"
            ;;
        *)
            echo "ERROR: unknown command '$CMD'. Use 'help' for usage." >&2
            exit 1
            ;;
    esac
fi
