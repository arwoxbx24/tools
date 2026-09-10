#!/bin/bash
# session-search.sh — CLI search for context sessions
# Usage:
#   session-search.sh --list [--limit N] [--since YYYY-MM-DD]
#   session-search.sh --keyword <word> [--limit N]
#   session-search.sh --session <id>
#   session-search.sh --issue <number>
#   session-search.sh --project-date <project> <YYYY-MM-DD> [--limit N]
# Issue: #230 (Context System v2)

set +e

REDIS_HOST="127.0.0.1"
REDIS_PORT="6379"

rcli() {
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" "$@" 2>/dev/null
}

# Check Redis
if ! rcli PING >/dev/null 2>&1; then
    echo "ERROR: Redis not available" >&2
    exit 1
fi

# Parse arguments
MODE=""
KEYWORD=""
SESSION_ID=""
ISSUE_NUM=""
PROJECT_NAME=""
PROJECT_DATE_NAME=""
PROJECT_DATE_DATE=""
LIMIT=10
SINCE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --list)         MODE="list"; shift ;;
        --keyword)      MODE="keyword"; KEYWORD="$2"; shift 2 ;;
        --session)      MODE="session"; SESSION_ID="$2"; shift 2 ;;
        --issue)        MODE="issue"; ISSUE_NUM="$2"; shift 2 ;;
        --project)      MODE="project"; PROJECT_NAME="$2"; shift 2 ;;
        --project-date) MODE="project-date"; PROJECT_DATE_NAME="$2"; PROJECT_DATE_DATE="$3"; shift 3 ;;
        --limit)        LIMIT="$2"; shift 2 ;;
        --since)        SINCE="$2"; shift 2 ;;
        --help|-h)      MODE="help"; shift ;;
        *)              echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# === HELP ===
if [ "$MODE" = "help" ] || [ -z "$MODE" ]; then
    echo "Session Search v2.2 — Context System (UTF-8 + prefix search + project index + project-date)"
    echo ""
    echo "Usage:"
    echo "  session-search.sh --list [--limit N] [--since YYYY-MM-DD]"
    echo "  session-search.sh --keyword <word> [--limit N]"
    echo "  session-search.sh --project <name> [--limit N]"
    echo "  session-search.sh --project-date <name> <YYYY-MM-DD> [--limit N]"
    echo "  session-search.sh --session <session_id>"
    echo "  session-search.sh --issue <number>"
    echo ""
    echo "Examples:"
    echo "  session-search.sh --list --limit 5"
    echo "  session-search.sh --keyword строй          # prefix search: matches стройремонт"
    echo "  session-search.sh --project stroyremont     # by project directory"
    echo "  session-search.sh --project-date transcription-dev 2026-04-09"
    echo "  session-search.sh --session 4c9c5f51-3747-49e3-b375-2f1d477e93d3"
    echo "  session-search.sh --issue 230"
    exit 0
fi

# === LIST MODE ===
if [ "$MODE" = "list" ]; then
    echo "=== Session Registry ==="
    echo ""

    # Collect all session:registry:* keys
    SESSIONS=()
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        sid="${key#session:registry:}"
        ts=$(rcli HGET "$key" "timestamp")
        msgs=$(rcli HGET "$key" "message_count")
        topics=$(rcli HGET "$key" "topics")
        issue=$(rcli HGET "$key" "active_issue")
        role=$(rcli HGET "$key" "role")
        model=$(rcli HGET "$key" "agent_model")
        project=$(rcli HGET "$key" "project")

        # Filter by --since
        if [ -n "$SINCE" ] && [ -n "$ts" ]; then
            ts_date="${ts%%T*}"
            if [[ "$ts_date" < "$SINCE" ]]; then
                continue
            fi
        fi

        SESSIONS+=("${ts}|${sid:0:12}|${msgs}|${role}/${model}|${project:-n/a}|${issue}|${topics}")
    done < <(rcli --scan --pattern "session:registry:*")

    if [ ${#SESSIONS[@]} -eq 0 ]; then
        echo "No sessions found in registry."
        echo ""
        echo "Tip: Sessions are indexed on save. Run session-indexer-daemon to index existing JSONL files."
        exit 0
    fi

    # Sort by timestamp (newest first) and limit
    printf '%s\n' "${SESSIONS[@]}" | sort -t'|' -k1 -r | head -"$LIMIT" | while IFS='|' read -r ts sid msgs role project issue topics; do
        printf "%-20s  %-14s  %4s msgs  %-18s  %-12s  issue:%-5s  %s\n" "$ts" "$sid" "$msgs" "$role" "$project" "$issue" "$topics"
    done

    echo ""
    echo "Total in registry: ${#SESSIONS[@]} sessions"
    exit 0
fi

# === KEYWORD MODE (with prefix + substring fallback) ===
if [ "$MODE" = "keyword" ]; then
    if [ -z "$KEYWORD" ]; then
        echo "ERROR: --keyword requires a word" >&2
        exit 1
    fi

    KEYWORD_LOWER=$(echo "$KEYWORD" | perl -C -pe '$_ = lc' 2>/dev/null || echo "$KEYWORD" | tr '[:upper:]' '[:lower:]')
    echo "=== Search: keyword='$KEYWORD_LOWER' ==="
    echo ""

    # Step 1: Exact match
    SESSION_IDS=$(rcli SMEMBERS "topic:index:${KEYWORD_LOWER}")
    SEARCH_METHOD="exact"

    # Step 2: Prefix match fallback
    if [ -z "$SESSION_IDS" ]; then
        SEARCH_METHOD="prefix"
        MATCHING_KEYS=$(rcli --scan --pattern "topic:index:${KEYWORD_LOWER}*" 2>/dev/null)
        if [ -n "$MATCHING_KEYS" ]; then
            SESSION_IDS=""
            while IFS= read -r key; do
                [ -z "$key" ] && continue
                MEMBERS=$(rcli SMEMBERS "$key")
                [ -n "$MEMBERS" ] && SESSION_IDS="${SESSION_IDS}${MEMBERS}"$'\n'
            done <<< "$MATCHING_KEYS"
            SESSION_IDS=$(echo "$SESSION_IDS" | sort -u | grep -v '^$')
        fi
    fi

    # Step 3: Substring match in topics field (scan all registries)
    if [ -z "$SESSION_IDS" ]; then
        SEARCH_METHOD="substring"
        SESSION_IDS=""
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            topics=$(rcli HGET "$key" "topics")
            if echo "$topics" | grep -qi "$KEYWORD_LOWER" 2>/dev/null; then
                sid="${key#session:registry:}"
                SESSION_IDS="${SESSION_IDS}${sid}"$'\n'
            fi
        done < <(rcli --scan --pattern "session:registry:*")
        SESSION_IDS=$(echo "$SESSION_IDS" | grep -v '^$')
    fi

    if [ -z "$SESSION_IDS" ]; then
        echo "No sessions found for keyword '$KEYWORD_LOWER' (tried: exact, prefix, substring)"
        echo ""
        echo "Available topic indexes (sample):"
        rcli --scan --pattern "topic:index:*" | sed 's/topic:index:/  /' | sort | head -20
        exit 0
    fi

    COUNT=0
    while IFS= read -r sid; do
        [ -z "$sid" ] && continue
        [ "$COUNT" -ge "$LIMIT" ] && break

        ts=$(rcli HGET "session:registry:${sid}" "timestamp")
        msgs=$(rcli HGET "session:registry:${sid}" "message_count")
        topics=$(rcli HGET "session:registry:${sid}" "topics")
        issue=$(rcli HGET "session:registry:${sid}" "active_issue")
        role=$(rcli HGET "session:registry:${sid}" "role")
        project=$(rcli HGET "session:registry:${sid}" "project")

        # Filter by --since
        if [ -n "$SINCE" ] && [ -n "$ts" ]; then
            ts_date="${ts%%T*}"
            if [[ "$ts_date" < "$SINCE" ]]; then
                continue
            fi
        fi

        printf "%-20s  %-14s  %4s msgs  %-12s  %-10s  issue:%-5s  %s\n" \
            "$ts" "${sid:0:12}" "$msgs" "$role" "${project:-n/a}" "$issue" "$topics"
        COUNT=$((COUNT + 1))
    done <<< "$SESSION_IDS"

    echo ""
    echo "Found: $COUNT sessions matching '$KEYWORD_LOWER' (method: $SEARCH_METHOD)"
    exit 0
fi

# === PROJECT MODE ===
if [ "$MODE" = "project" ]; then
    if [ -z "$PROJECT_NAME" ]; then
        echo "ERROR: --project requires a project name" >&2
        exit 1
    fi

    PROJECT_LOWER=$(echo "$PROJECT_NAME" | perl -C -pe '$_ = lc' 2>/dev/null || echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
    echo "=== Search: project='$PROJECT_LOWER' ==="
    echo ""

    # Step 1: Exact match
    SESSION_IDS=$(rcli SMEMBERS "project:index:${PROJECT_LOWER}")

    # Step 2: Prefix match fallback
    if [ -z "$SESSION_IDS" ]; then
        MATCHING_KEYS=$(rcli --scan --pattern "project:index:${PROJECT_LOWER}*" 2>/dev/null)
        if [ -n "$MATCHING_KEYS" ]; then
            SESSION_IDS=""
            while IFS= read -r key; do
                [ -z "$key" ] && continue
                MEMBERS=$(rcli SMEMBERS "$key")
                [ -n "$MEMBERS" ] && SESSION_IDS="${SESSION_IDS}${MEMBERS}"$'\n'
            done <<< "$MATCHING_KEYS"
            SESSION_IDS=$(echo "$SESSION_IDS" | sort -u | grep -v '^$')
        fi
    fi

    # Step 3: Scan registry project field
    if [ -z "$SESSION_IDS" ]; then
        SESSION_IDS=""
        while IFS= read -r key; do
            [ -z "$key" ] && continue
            proj=$(rcli HGET "$key" "project")
            if echo "$proj" | grep -qi "$PROJECT_LOWER" 2>/dev/null; then
                sid="${key#session:registry:}"
                SESSION_IDS="${SESSION_IDS}${sid}"$'\n'
            fi
        done < <(rcli --scan --pattern "session:registry:*")
        SESSION_IDS=$(echo "$SESSION_IDS" | grep -v '^$')
    fi

    if [ -z "$SESSION_IDS" ]; then
        echo "No sessions found for project '$PROJECT_LOWER'"
        echo ""
        echo "Available projects:"
        rcli --scan --pattern "project:index:*" | sed 's/project:index:/  /' | sort
        exit 0
    fi

    COUNT=0
    while IFS= read -r sid; do
        [ -z "$sid" ] && continue
        [ "$COUNT" -ge "$LIMIT" ] && break

        ts=$(rcli HGET "session:registry:${sid}" "timestamp")
        msgs=$(rcli HGET "session:registry:${sid}" "message_count")
        topics=$(rcli HGET "session:registry:${sid}" "topics")
        issue=$(rcli HGET "session:registry:${sid}" "active_issue")
        role=$(rcli HGET "session:registry:${sid}" "role")

        printf "%-20s  %-14s  %4s msgs  %-15s  issue:%-5s  %s\n" \
            "$ts" "${sid:0:12}" "$msgs" "$role" "$issue" "$topics"
        COUNT=$((COUNT + 1))
    done <<< "$SESSION_IDS"

    echo ""
    echo "Found: $COUNT sessions for project '$PROJECT_LOWER'"
    exit 0
fi

# === PROJECT-DATE MODE ===
if [ "$MODE" = "project-date" ]; then
    if [ -z "$PROJECT_DATE_NAME" ]; then
        echo "ERROR: --project-date requires a project name" >&2
        exit 1
    fi
    if [ -z "$PROJECT_DATE_DATE" ]; then
        echo "ERROR: --project-date requires a date (YYYY-MM-DD)" >&2
        exit 1
    fi

    PROJ_LOWER=$(echo "$PROJECT_DATE_NAME" | perl -C -pe '$_ = lc' 2>/dev/null || echo "$PROJECT_DATE_NAME" | tr '[:upper:]' '[:lower:]')
    echo "=== Sessions: project='$PROJ_LOWER' date='$PROJECT_DATE_DATE' ==="
    echo ""

    COUNT=0
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        proj=$(rcli HGET "$key" "project")
        ts=$(rcli HGET "$key" "timestamp")
        ts_date="${ts%%T*}"

        # Match project (case-insensitive substring) AND date prefix
        PROJ_MATCH=$(echo "$proj" | grep -qi "$PROJ_LOWER" 2>/dev/null && echo "yes" || echo "no")
        if [ "$PROJ_MATCH" = "yes" ] && [ "$ts_date" = "$PROJECT_DATE_DATE" ]; then
            sid="${key#session:registry:}"
            msgs=$(rcli HGET "$key" "message_count")
            topics=$(rcli HGET "$key" "topics")
            issue=$(rcli HGET "$key" "active_issue")
            role=$(rcli HGET "$key" "role")
            description=$(rcli HGET "$key" "description")
            intent=$(rcli HGET "$key" "intent")

            printf "%-20s  %-14s  %4s msgs  %-15s  issue:%-5s\n" \
                "$ts" "${sid:0:12}" "$msgs" "$role" "$issue"
            [ -n "$description" ] && printf "  desc: %s\n" "$description"
            [ -n "$intent" ]      && printf "  intent: %s\n" "$intent"
            [ -n "$topics" ]      && printf "  topics: %s\n" "$topics"
            echo ""

            COUNT=$((COUNT + 1))
            [ "$COUNT" -ge "$LIMIT" ] && break
        fi
    done < <(rcli --scan --pattern "session:registry:*")

    if [ "$COUNT" -eq 0 ]; then
        echo "No sessions found for project='$PROJ_LOWER' on date='$PROJECT_DATE_DATE'"
        echo ""
        echo "Tip: Check available dates with: session-search.sh --project $PROJECT_DATE_NAME"
    else
        echo "Found: $COUNT sessions"
    fi
    exit 0
fi

# === SESSION MODE ===
if [ "$MODE" = "session" ]; then
    if [ -z "$SESSION_ID" ]; then
        echo "ERROR: --session requires a session ID" >&2
        exit 1
    fi

    echo "=== Session: $SESSION_ID ==="
    echo ""

    # Try registry first
    REG_EXISTS=$(rcli EXISTS "session:registry:${SESSION_ID}")
    if [ "$REG_EXISTS" = "1" ]; then
        echo "--- Registry ---"
        rcli HGETALL "session:registry:${SESSION_ID}" | paste - - | while IFS=$'\t' read -r key val; do
            printf "  %-15s %s\n" "$key:" "$val"
        done
        # Highlight new structured fields if present
        _desc=$(rcli HGET "session:registry:${SESSION_ID}" "description")
        _intent=$(rcli HGET "session:registry:${SESSION_ID}" "intent")
        if [ -n "$_desc" ] || [ -n "$_intent" ]; then
            echo ""
            echo "--- Structured Description ---"
            [ -n "$_desc" ]   && printf "  description: %s\n" "$_desc"
            [ -n "$_intent" ] && printf "  intent:      %s\n" "$_intent"
        fi
        echo ""
    fi

    # Try archive
    ARCHIVE=$(rcli GET "context:archive:${SESSION_ID}")
    if [ -n "$ARCHIVE" ] && [ "$ARCHIVE" != "(nil)" ]; then
        echo "--- Archive (last_messages) ---"
        echo "$ARCHIVE" | jq -r '.last_messages // "none"' 2>/dev/null | head -30
    else
        echo "No archive found for this session."
        echo ""
        echo "Searching context:history..."
        # Fallback: search history list
        HIST_LEN=$(rcli LLEN "context:history")
        FOUND=false
        for i in $(seq 0 $((HIST_LEN - 1))); do
            ENTRY=$(rcli LINDEX "context:history" "$i")
            ENTRY_SID=$(echo "$ENTRY" | jq -r '.session_id // empty' 2>/dev/null)
            if [ "$ENTRY_SID" = "$SESSION_ID" ]; then
                echo "$ENTRY" | jq -r '.last_messages // "none"' 2>/dev/null | head -30
                FOUND=true
                break
            fi
        done
        [ "$FOUND" = false ] && echo "Session not found in history either."
    fi

    exit 0
fi

# === ISSUE MODE ===
if [ "$MODE" = "issue" ]; then
    if [ -z "$ISSUE_NUM" ]; then
        echo "ERROR: --issue requires a number" >&2
        exit 1
    fi

    echo "=== Sessions for issue #$ISSUE_NUM ==="
    echo ""

    COUNT=0
    while IFS= read -r key; do
        [ -z "$key" ] && continue
        issue=$(rcli HGET "$key" "active_issue")
        if [ "$issue" = "$ISSUE_NUM" ]; then
            sid="${key#session:registry:}"
            ts=$(rcli HGET "$key" "timestamp")
            msgs=$(rcli HGET "$key" "message_count")
            topics=$(rcli HGET "$key" "topics")
            role=$(rcli HGET "$key" "role")

            printf "%-20s  %-14s  %4s msgs  %-15s  %s\n" \
                "$ts" "${sid:0:12}" "$msgs" "$role" "$topics"
            COUNT=$((COUNT + 1))
            [ "$COUNT" -ge "$LIMIT" ] && break
        fi
    done < <(rcli --scan --pattern "session:registry:*")

    echo ""
    echo "Found: $COUNT sessions for issue #$ISSUE_NUM"
    exit 0
fi
