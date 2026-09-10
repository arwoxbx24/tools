#!/bin/bash
# agent-tool-context-search.sh — fast session context finder (1-2 Redis queries max)
# Usage:
#   agent-tool-context-search.sh --project NAME
#   agent-tool-context-search.sh --issue NUM
#   agent-tool-context-search.sh --topic KEYWORD
# Issue: #5 (Redis context search optimization)

set +e

REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"
MAX_RESULTS=5

rcli() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

# ---- help ----
show_help() {
    cat <<'EOF'
agent-tool-context-search.sh — fast session context finder

Usage:
  agent-tool-context-search.sh --project NAME    search by project name
  agent-tool-context-search.sh --issue NUM       search by GitHub issue number
  agent-tool-context-search.sh --topic KEYWORD   search by topic keyword

Options:
  --limit N      max results (default: 5)
  --help, -h     show this help

Output: compact table — session_id | timestamp | project | issue | description

Examples:
  agent-tool-context-search.sh --project transcription-dev
  agent-tool-context-search.sh --issue 230
  agent-tool-context-search.sh --topic redis
EOF
    exit 0
}

# ---- args ----
MODE=""
QUERY=""
LIMIT=$MAX_RESULTS

while [ $# -gt 0 ]; do
    case "$1" in
        --project) MODE="project"; QUERY="$2"; shift 2 ;;
        --issue)   MODE="issue";   QUERY="$2"; shift 2 ;;
        --topic)   MODE="topic";   QUERY="$2"; shift 2 ;;
        --limit)   LIMIT="$2";     shift 2 ;;
        --help|-h) show_help ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$MODE" ]; then
    show_help
fi

# ---- Redis check ----
if ! rcli PING >/dev/null 2>&1; then
    echo "ERROR: Redis unavailable at ${REDIS_HOST}:${REDIS_PORT}" >&2
    exit 1
fi

# ---- output helpers ----
HEADER_PRINTED=0

print_header() {
    if [ "$HEADER_PRINTED" -eq 0 ]; then
        printf "%-12s  %-19s  %-22s  %-6s  %s\n" \
            "SESSION_ID" "TIMESTAMP" "PROJECT" "ISSUE" "DESCRIPTION"
        printf "%-12s  %-19s  %-22s  %-6s  %s\n" \
            "------------" "-------------------" "----------------------" "------" "-----------"
        HEADER_PRINTED=1
    fi
}

print_row() {
    local sid="$1" ts="$2" proj="$3" issue="$4" desc="$5"
    printf "%-12s  %-19s  %-22s  %-6s  %s\n" \
        "${sid:0:12}" "${ts:0:19}" "${proj:0:22}" "${issue:-n/a}" "${desc:0:60}"
}

# Fetch fields from registry or context:archive fallback
# Sets global: _SID_TS _SID_PROJ _SID_ISSUE _SID_TOPICS
fetch_session_fields() {
    local sid="$1"
    _SID_TS="" _SID_PROJ="" _SID_ISSUE="" _SID_TOPICS=""

    # Try registry first (fast HGET)
    local reg_ts
    reg_ts=$(rcli HGET "session:registry:${sid}" "timestamp" 2>/dev/null)

    if [ -n "$reg_ts" ] && [ "$reg_ts" != "(nil)" ]; then
        _SID_TS="$reg_ts"
        _SID_PROJ=$(rcli HGET "session:registry:${sid}" "project" 2>/dev/null)
        _SID_ISSUE=$(rcli HGET "session:registry:${sid}" "active_issue" 2>/dev/null)
        _SID_TOPICS=$(rcli HGET "session:registry:${sid}" "topics" 2>/dev/null)
    else
        # Fallback: context:archive JSON blob
        local arch
        arch=$(rcli GET "context:archive:${sid}" 2>/dev/null)
        if [ -n "$arch" ] && [ "$arch" != "(nil)" ]; then
            _SID_TS=$(echo "$arch" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('timestamp',''))" 2>/dev/null)
            _SID_PROJ=$(echo "$arch" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('project',''))" 2>/dev/null)
            _SID_ISSUE=$(echo "$arch" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('active_issue',''))" 2>/dev/null)
            _SID_TOPICS=$(echo "$arch" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('topics',''))" 2>/dev/null)
        fi
    fi
}

# Fetch registry fields for a session_id, print row
print_session() {
    local sid="$1"
    [ -z "$sid" ] && return

    fetch_session_fields "$sid"

    local desc
    if [ -n "$_SID_TOPICS" ] && [ "$_SID_TOPICS" != "None" ]; then
        desc=$(echo "$_SID_TOPICS" | tr ' ' '\n' | head -5 | tr '\n' ' ' | sed 's/ $//')
    else
        desc="(no topics)"
    fi

    print_row "$sid" "${_SID_TS:-unknown}" "${_SID_PROJ:-n/a}" "$_SID_ISSUE" "$desc"
}

# ================================================================
# MODE: project — Query 1: project:index:<name>  (1 Redis call)
#                 Fallback: scan session:registry:* project field
# ================================================================
if [ "$MODE" = "project" ]; then
    QUERY_LOWER=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')

    # Query 1: exact index lookup
    SIDS=$(rcli SMEMBERS "project:index:${QUERY_LOWER}" 2>/dev/null)

    # Query 2 (fallback): prefix scan on index keys
    if [ -z "$SIDS" ]; then
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            M=$(rcli SMEMBERS "$key" 2>/dev/null)
            [ -n "$M" ] && SIDS="${SIDS}"$'\n'"$M"
        done < <(rcli --scan --pattern "project:index:${QUERY_LOWER}*" 2>/dev/null)
        SIDS=$(echo "$SIDS" | sort -u | grep -v '^$')
    fi

    print_header
    COUNT=0
    while IFS= read -r sid; do
        [ -z "$sid" ] && continue
        [ "$COUNT" -ge "$LIMIT" ] && break
        print_session "$sid"
        COUNT=$((COUNT + 1))
    done <<< "$SIDS"

    echo ""
    echo "Results: ${COUNT} session(s) for project '${QUERY_LOWER}'"
    exit 0
fi

# ================================================================
# MODE: issue — Query 1: issue:index:<num>  (1 Redis call)
#               Fallback: scan session:registry:* active_issue field
# ================================================================
if [ "$MODE" = "issue" ]; then
    # Query 1: issue index (if exists)
    SIDS=$(rcli SMEMBERS "issue:index:${QUERY}" 2>/dev/null)

    # Query 2 (fallback): scan registry
    if [ -z "$SIDS" ]; then
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            issue_val=$(rcli HGET "$key" "active_issue" 2>/dev/null)
            if [ "$issue_val" = "$QUERY" ]; then
                SIDS="${SIDS}"$'\n'"${key#session:registry:}"
            fi
        done < <(rcli --scan --pattern "session:registry:*" 2>/dev/null)
        SIDS=$(echo "$SIDS" | grep -v '^$')
    fi

    print_header
    COUNT=0
    while IFS= read -r sid; do
        [ -z "$sid" ] && continue
        [ "$COUNT" -ge "$LIMIT" ] && break
        print_session "$sid"
        COUNT=$((COUNT + 1))
    done <<< "$SIDS"

    echo ""
    echo "Results: ${COUNT} session(s) for issue #${QUERY}"
    exit 0
fi

# ================================================================
# MODE: topic — Query 1: topic:index:<keyword>  (1 Redis call)
#               Query 2 (fallback): prefix scan on topic:index:*
#               Query 3 (last resort): substring in registry topics field
# ================================================================
if [ "$MODE" = "topic" ]; then
    QUERY_LOWER=$(echo "$QUERY" | tr '[:upper:]' '[:lower:]')

    # Query 1: exact topic index
    SIDS=$(rcli SMEMBERS "topic:index:${QUERY_LOWER}" 2>/dev/null)

    # Query 2: prefix index scan
    if [ -z "$SIDS" ]; then
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            M=$(rcli SMEMBERS "$key" 2>/dev/null)
            [ -n "$M" ] && SIDS="${SIDS}"$'\n'"$M"
        done < <(rcli --scan --pattern "topic:index:${QUERY_LOWER}*" 2>/dev/null)
        SIDS=$(echo "$SIDS" | sort -u | grep -v '^$')
    fi

    # Query 3: substring scan in registry topics field
    if [ -z "$SIDS" ]; then
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            topics=$(rcli HGET "$key" "topics" 2>/dev/null)
            case "${topics,,}" in
                *"${QUERY_LOWER}"*) SIDS="${SIDS}"$'\n'"${key#session:registry:}" ;;
            esac
        done < <(rcli --scan --pattern "session:registry:*" 2>/dev/null)
        SIDS=$(echo "$SIDS" | grep -v '^$')
    fi

    # Also check context:latest
    LATEST=$(rcli GET "context:latest" 2>/dev/null)
    if [ -n "$LATEST" ] && [ "$LATEST" != "(nil)" ]; then
        LATEST_TOPICS=$(echo "$LATEST" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('topics',''))" 2>/dev/null)
        case "${LATEST_TOPICS,,}" in
            *"${QUERY_LOWER}"*)
                LATEST_SID=$(echo "$LATEST" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session_id',''))" 2>/dev/null)
                [ -n "$LATEST_SID" ] && SIDS="${LATEST_SID}"$'\n'"${SIDS}"
                ;;
        esac
    fi

    SIDS=$(echo "$SIDS" | sort -u | grep -v '^$')

    print_header
    COUNT=0
    while IFS= read -r sid; do
        [ -z "$sid" ] && continue
        [ "$COUNT" -ge "$LIMIT" ] && break
        print_session "$sid"
        COUNT=$((COUNT + 1))
    done <<< "$SIDS"

    echo ""
    echo "Results: ${COUNT} session(s) matching topic '${QUERY_LOWER}'"
    exit 0
fi
