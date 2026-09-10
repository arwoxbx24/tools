#!/bin/bash

# Context Recovery Script
# Searches Redis and git history for recent context
# Usage: context-recovery.sh [search_query]

set -euo pipefail

# Set VERBOSE=1 for full diagnostic output
QUERY="${1:-}"
REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
WORKING_DIR="/root/claude-projects"

V() { [[ "${VERBOSE:-0}" == "1" ]] && echo "$@" || true; }

# Function to format timestamp
format_time() {
    local timestamp="$1"
    if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$timestamp"
    else
        echo "$timestamp"
    fi
}

# Function to search Redis (verbose only)
search_redis() {
    local pattern="$1"

    if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING &>/dev/null; then
        echo "WARNING: Redis not available" >&2
        return 1
    fi

    local keys
    keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --scan --pattern "$pattern" 2>/dev/null | sort)
    [ -z "$keys" ] && return 0

    while IFS= read -r key; do
        [ -z "$key" ] && continue
        local ttl
        ttl=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" TTL "$key" 2>/dev/null || echo "-2")
        [ "$ttl" = "-2" ] && continue

        local value key_type
        key_type=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" TYPE "$key" 2>/dev/null || echo "none")
        case "$key_type" in
            string) value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$key" 2>/dev/null | head -c 500) ;;
            hash)   value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" HGETALL "$key" 2>/dev/null | head -20) ;;
            list)   value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" LRANGE "$key" 0 10 2>/dev/null) ;;
            *)      value="<$key_type>" ;;
        esac
        V "Key: $key | Type: $key_type"
        [ -n "$value" ] && V "$value"
    done <<< "$keys"
}

# Function to get recent sessions — prints one summary line for the most recent
get_recent_sessions() {
    local limit="${1:-3}"

    if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING &>/dev/null; then
        echo "WARNING: Redis not available" >&2
        return 1
    fi

    local session_keys
    session_keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --scan --pattern "session:*" 2>/dev/null | sort -r | head -n "$limit")
    [ -z "$session_keys" ] && return 0

    local SESSIONS_INDEX="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects/sessions-index.json"
    local sessions_index_data=""
    [ -f "$SESSIONS_INDEX" ] && sessions_index_data=$(cat "$SESSIONS_INDEX" 2>/dev/null)

    local first=1
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        if [[ "$first" == "1" ]]; then
            local task project timestamp branch=""
            task=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" HGET "$key" "task" 2>/dev/null)
            project=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" HGET "$key" "project" 2>/dev/null)
            timestamp=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" HGET "$key" "timestamp" 2>/dev/null)
            [ -n "$timestamp" ] && timestamp=$(format_time "$timestamp")
            if [ -n "$sessions_index_data" ]; then
                local session_uuid
                session_uuid=$(echo "$key" | sed 's|session:[^:]*:||')
                branch=$(echo "$sessions_index_data" | jq -r --arg sid "$session_uuid" '.entries[] | select(.sessionId == $sid) | .gitBranch // ""' 2>/dev/null)
            fi
            echo "Last session: ${timestamp:-unknown} | project: ${project:-?} | ${task:-no task}${branch:+ | branch: $branch}"
            first=0
        fi
        V "Session key: $key"
    done <<< "$session_keys"
}

# Function to search git log (verbose only)
search_git() {
    local query="$1"
    [ ! -d "$WORKING_DIR/.git" ] && return 0
    cd "$WORKING_DIR" || return 1
    if [ -n "$query" ]; then
        git log --all --oneline --grep="$query" -i --max-count=10 2>/dev/null | while IFS= read -r line; do V "  git: $line"; done
    else
        git log --oneline --max-count=10 2>/dev/null | while IFS= read -r line; do V "  git: $line"; done
    fi
}

# Function to search context keys (verbose only)
search_context_keys() {
    local query="$1"

    if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING &>/dev/null; then
        return 1
    fi

    local context_keys
    if [ -n "$query" ]; then
        context_keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --scan --pattern "context:*$query*" 2>/dev/null)
    else
        context_keys=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" --scan --pattern "context:*" 2>/dev/null | head -10)
    fi
    [ -z "$context_keys" ] && return 0

    while IFS= read -r key; do
        [ -z "$key" ] && continue
        local value
        value=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "$key" 2>/dev/null | head -c 300)
        V "Context key: $key"
        [ -n "$value" ] && V "$value"
    done <<< "$context_keys"
}

# Main logic
if [ -n "$QUERY" ]; then
    search_redis "session:*$QUERY*" || true
    search_context_keys "$QUERY" || true
    search_git "$QUERY"
else
    get_recent_sessions 3 || true
    search_context_keys "" || true
    search_git ""
fi

# === Active Plans Check (Plan Lifecycle) ===
PLANS_DIR="/root/workspaces/tools/acc1-scripts/plans"
if [ -d "$PLANS_DIR" ]; then
    PLAN_FILES=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null || true)
    if [ -n "$PLAN_FILES" ]; then
        ACTIVE_COUNT=0
        STALE_COUNT=0
        while IFS= read -r pfile; do
            [ -z "$pfile" ] && continue
            P_STATUS=$(awk '/<!--PLAN_META/{f=1} f && /STATUS:/{match($0,/STATUS:\s*([a-z_]+)/,a); print a[1]; exit} /-->/{f=0}' "$pfile" 2>/dev/null)
            [ -z "$P_STATUS" ] && P_STATUS=$(grep -oP 'STATUS:\s*\K\w+' "$pfile" 2>/dev/null | head -1 || true)
            P_TITLE=$(grep -oP 'TITLE:\s*\K.*' "$pfile" 2>/dev/null | head -1 || true)
            P_PROJECT=$(grep -oP 'PROJECT:\s*\K\w+' "$pfile" 2>/dev/null | head -1 || true)
            # === PROJECT SCOPE FILTER (session isolation) ===
            _SESSION_PROJECT=""
            if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
                _SESSION_PROJECT=$(cat "/tmp/.project-dir-lock-${CLAUDE_SESSION_ID}" 2>/dev/null || \
                                   redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "session:sticky:${CLAUDE_SESSION_ID}" 2>/dev/null || true)
            fi
            # Fallback: derive from PWD
            [[ -z "$_SESSION_PROJECT" ]] && _SESSION_PROJECT=$(basename "$PWD" 2>/dev/null || true)
            # Skip plans for other projects (only when both are known and differ)
            if [[ -n "$_SESSION_PROJECT" && -n "$P_PROJECT" && "$_SESSION_PROJECT" != "$P_PROJECT" ]]; then
                continue
            fi
            P_BASENAME=$(basename "$pfile")

            case "$P_STATUS" in
                created|in_progress)
                    echo "ACTIVE PLAN [${P_STATUS}]: ${P_TITLE:-$P_BASENAME} (project: ${P_PROJECT:-unknown}) — $pfile"
                    ACTIVE_COUNT=$((ACTIVE_COUNT + 1))
                    ;;
                stale|abandoned)
                    echo "WARNING: STALE PLAN [${P_STATUS}]: ${P_TITLE:-$P_BASENAME} (project: ${P_PROJECT:-unknown})"
                    STALE_COUNT=$((STALE_COUNT + 1))
                    if [ -n "$P_PROJECT" ]; then
                        redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" SET "plan:stale-block:${P_PROJECT}" "$pfile" EX 7200 >/dev/null 2>&1 || true
                    fi
                    ;;
                completed)
                    ;;
                *)
                    V "Legacy plan (no metadata): $P_BASENAME"
                    ;;
            esac
        done <<< "$PLAN_FILES"

        if [ "$STALE_COUNT" -gt 0 ]; then
            echo "WARNING: $STALE_COUNT stale plan(s) — close or archive before creating new plans for same project."
        fi
    fi
fi

# === V396: Agent Checkpoints ===
CHECKPOINT_KEYS=$(redis-cli --scan --pattern "checkpoint:*" 2>/dev/null | grep -v ":index:" | grep -v ":partial:" | head -20)
PARTIAL_KEYS=$(redis-cli --scan --pattern "checkpoint:partial:*" 2>/dev/null | head -10)

if [[ -n "$PARTIAL_KEYS" ]]; then
    echo "WARNING: PARTIAL checkpoints found (agent crashed mid-save):"
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        SUMMARY=$(redis-cli HGET "$key" "task_summary" 2>/dev/null)
        PROJECT=$(redis-cli HGET "$key" "project" 2>/dev/null)
        TS=$(redis-cli HGET "$key" "timestamp" 2>/dev/null)
        echo "  [PARTIAL] ${PROJECT}: ${SUMMARY} (${TS})"
        echo "  Resume: bash /root/workspaces/tools/acc1-scripts/scripts/agent-state-saver.sh --project ${PROJECT} --summary '${SUMMARY}' --type build"
    done <<< "$PARTIAL_KEYS"
fi

if [[ -n "$CHECKPOINT_KEYS" ]]; then
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        L1=$(redis-cli HGET "$key" "level1_ok" 2>/dev/null)
        L2=$(redis-cli HGET "$key" "level2_ok" 2>/dev/null)
        L3=$(redis-cli HGET "$key" "level3_ok" 2>/dev/null)
        if [[ "$L1" != "1" || "$L2" != "1" || "$L3" != "1" ]]; then
            SUMMARY=$(redis-cli HGET "$key" "task_summary" 2>/dev/null)
            echo "INCOMPLETE CHECKPOINT: L1=${L1:-?} L2=${L2:-?} L3=${L3:-?} — ${SUMMARY}"
        fi
    done <<< "$CHECKPOINT_KEYS"
fi

# === Cross-Session Handoff Restoration ===
PROJECT=$(basename "$PWD")
if [[ "$PROJECT" != "claude-projects" ]]; then
    HANDOFF_EXISTS=$(redis-cli EXISTS "handoff:${PROJECT}" 2>/dev/null || echo "0")
    if [[ "$HANDOFF_EXISTS" == "1" ]]; then
        H_PLAN=$(redis-cli HGET "handoff:${PROJECT}" plan_path 2>/dev/null || echo "none")
        H_PHASE=$(redis-cli HGET "handoff:${PROJECT}" phase 2>/dev/null || echo "0")
        H_TIER=$(redis-cli HGET "handoff:${PROJECT}" tier 2>/dev/null || echo "STANDARD")
        H_SESSION=$(redis-cli HGET "handoff:${PROJECT}" session_id 2>/dev/null || echo "unknown")

        V "HANDOFF restored: plan=${H_PLAN} phase=${H_PHASE} tier=${H_TIER} prev_session=${H_SESSION}"

        if [[ "$H_PLAN" != "none" ]] && [[ -f "$H_PLAN" ]]; then
            redis-cli SET "plan:active:${SESSION_ID:-unknown}" "$H_PLAN" EX 86400 >/dev/null 2>&1
        fi
        if [[ -n "$H_TIER" ]]; then
            redis-cli SET "task:tier:${SESSION_ID:-unknown}" "$H_TIER" EX 28800 >/dev/null 2>&1
        fi
    fi
fi

# === Teamlead-specific context restore (ADR-006) ===
if [[ "$PROJECT" == ".teamlead-agent" ]] || \
   [[ -n "${SESSION_ID:-}" && "$(redis-cli GET "teamlead:session:${SESSION_ID}" 2>/dev/null)" == *"active"* ]]; then
    _TL_STATE="/root/claude-projects/.teamlead-agent/state/last-session.json"
    if [[ -f "$_TL_STATE" ]]; then
        echo "TEAMLEAD RESTORE: $(jq -r '"\(.started_at // "?") plan=\(.last_plan // "none") phase=\(.last_phase // "0")"' "$_TL_STATE" 2>/dev/null || echo 'parse error')"
    fi
    _TL_PLAN=$(redis-cli HGET "handoff:.teamlead-agent" plan_path 2>/dev/null || echo "")
    if [[ -n "$_TL_PLAN" && -f "$_TL_PLAN" ]]; then
        redis-cli SET "plan:active:${SESSION_ID:-unknown}" "$_TL_PLAN" EX 86400 &>/dev/null || true
        echo "TEAMLEAD RESTORE: Active plan → ${_TL_PLAN}"
    fi
fi

# === Git Tags (golden/backup) — verbose only ===
GOLDEN_TAGS=$(git -C "$WORKING_DIR" tag -l "golden-*" --sort=-creatordate 2>/dev/null | head -5)
if [ -n "$GOLDEN_TAGS" ]; then
    echo "$GOLDEN_TAGS" | while read -r tag; do
        TAG_MSG=$(git -C "$WORKING_DIR" tag -l -n1 "$tag" 2>/dev/null | sed "s/^$tag *//")
        V "Golden tag: $tag — $TAG_MSG"
    done
fi

# === Search Quality Alert ===
SEARCH_ALERT=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" GET "search:alert" 2>/dev/null)
if [ -n "$SEARCH_ALERT" ] && [ "$SEARCH_ALERT" != "(nil)" ]; then
    echo "WARNING: SEARCH QUALITY ALERT — $SEARCH_ALERT"
fi

# === Recent Sessions Trim: keep max 5 entries in MEMORY.md ===
MEMORY_FILE="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects/memory/MEMORY.md"
MAX_SESSIONS=5
if [ -f "$MEMORY_FILE" ]; then
    python3 - "$MEMORY_FILE" "$MAX_SESSIONS" <<'PYEOF' 2>/dev/null || true
import sys, re

mem_file = sys.argv[1]
max_sessions = int(sys.argv[2])

with open(mem_file) as f:
    content = f.read()

# Find AUTO-UPDATE-START ... AUTO-UPDATE-END block
start_marker = '<!-- AUTO-UPDATE-START -->'
end_marker = '<!-- AUTO-UPDATE-END -->'

s_pos = content.find(start_marker)
e_pos = content.find(end_marker)

if s_pos == -1 or e_pos == -1:
    sys.exit(0)

block_start = s_pos + len(start_marker)
block_end = e_pos

block = content[block_start:block_end]
entries = [l for l in block.splitlines(keepends=True) if l.startswith('- ')]

# Trim each entry to max 150 chars (strip trailing newline, truncate, restore newline)
def trim_entry(line):
    stripped = line.rstrip('\n')
    if len(stripped) > 150:
        stripped = stripped[:147] + '...'
    return stripped + '\n'

entries = [trim_entry(e) for e in entries]

if len(entries) <= max_sessions:
    # Still apply char limit even if count is fine
    new_block = start_marker + '\n' + ''.join(entries) + end_marker
    new_content = content[:s_pos] + new_block + content[e_pos + len(end_marker):]
    with open(mem_file, 'w') as f:
        f.write(new_content)
    sys.exit(0)

# Keep newest max_sessions entries (last N lines)
kept = entries[-max_sessions:]
new_block = start_marker + '\n' + ''.join(kept) + end_marker
new_content = content[:s_pos] + new_block + content[e_pos + len(end_marker):]

with open(mem_file, 'w') as f:
    f.write(new_content)

print(f'Trimmed Recent Sessions: {len(entries)} → {max_sessions}')
PYEOF
fi
