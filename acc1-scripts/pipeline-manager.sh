#!/bin/bash
# pipeline-manager.sh — V_PIPELINE Phase Registry Manager
# Manages pipeline phases in Redis for modular architecture orchestration
# Usage: bash pipeline-manager.sh COMMAND [OPTIONS]

set +e

# === SESSION ID ===
SESSION_ID="${CLAUDE_SESSION_ID:-}"
[[ -z "$SESSION_ID" ]] && SESSION_ID=$(cat /tmp/.claude-session-id 2>/dev/null || echo "proc-${PPID:-$$}")

COMMAND="${1:-status}"
shift 2>/dev/null

# === PARSE OPTIONS ===
PHASES=""
PROJECT=""
PHASE_IDX=""
ARTIFACTS=""
SUMMARY=""
STACK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phases) PHASES="$2"; shift 2 ;;
        --project) PROJECT="$2"; shift 2 ;;
        --phase) PHASE_IDX="$2"; shift 2 ;;
        --artifacts) ARTIFACTS="$2"; shift 2 ;;
        --summary) SUMMARY="$2"; shift 2 ;;
        --stack) STACK="$2"; shift 2 ;;
        --session) SESSION_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

CONFIG_KEY="pipeline:${SESSION_ID}:config"
CURRENT_KEY="pipeline:${SESSION_ID}:current"
TTL=86400

case "$COMMAND" in
    init)
        [[ -z "$PHASES" ]] && echo "ERROR: --phases required (comma-separated)" && exit 1
        [[ -z "$PROJECT" ]] && PROJECT="unknown"
        if [[ -z "$STACK" ]]; then
            echo "ERROR: --stack is required for pipeline init. Example: --stack 'React+Node.js'"
            exit 1
        fi

        # Convert comma-separated to JSON array
        PHASES_JSON=$(echo "$PHASES" | tr ',' '\n' | jq -R . | jq -s .)
        PHASE_COUNT=$(echo "$PHASES_JSON" | jq length)

        redis-cli HSET "$CONFIG_KEY" \
            "phases" "$PHASES_JSON" \
            "phase_count" "$PHASE_COUNT" \
            "current_phase" "0" \
            "project" "$PROJECT" \
            "stack" "${STACK:-}" \
            "created_at" "$(date -Iseconds)" \
            "status" "active" >/dev/null 2>&1
        redis-cli EXPIRE "$CONFIG_KEY" $TTL >/dev/null 2>&1

        redis-cli SET "$CURRENT_KEY" "0" EX $TTL >/dev/null 2>&1

        # Initialize each phase
        IFS=',' read -ra PHASE_ARRAY <<< "$PHASES"
        for i in "${!PHASE_ARRAY[@]}"; do
            PHASE_KEY="pipeline:${SESSION_ID}:phase:${i}"
            STATUS="pending"
            [[ $i -eq 0 ]] && STATUS="active"
            redis-cli HSET "$PHASE_KEY" \
                "name" "${PHASE_ARRAY[$i]}" \
                "index" "$i" \
                "status" "$STATUS" \
                "started_at" "" \
                "completed_at" "" \
                "agent_ids" "" \
                "artifacts" "[]" \
                "dod_verified" "0" \
                "handoff_token" "" >/dev/null 2>&1
            redis-cli EXPIRE "$PHASE_KEY" $TTL >/dev/null 2>&1
        done

        # Mark phase 0 as started
        redis-cli HSET "pipeline:${SESSION_ID}:phase:0" "started_at" "$(date -Iseconds)" >/dev/null 2>&1

        echo "PIPELINE_INIT: ${PHASE_COUNT} phases | Project: ${PROJECT}"
        echo "Phases: ${PHASES}"
        echo "Current: 0 (${PHASE_ARRAY[0]})"
        [[ -n "$STACK" ]] && echo "Stack: ${STACK}"
        echo "Session: ${SESSION_ID:0:12}"
        ;;

    advance)
        [[ -z "$PHASE_IDX" ]] && PHASE_IDX=$(redis-cli GET "$CURRENT_KEY" 2>/dev/null)
        [[ -z "$PHASE_IDX" ]] && echo "ERROR: No active pipeline" && exit 1

        PHASE_COUNT=$(redis-cli HGET "$CONFIG_KEY" "phase_count" 2>/dev/null)
        NEXT_IDX=$((PHASE_IDX + 1))

        # Mark current phase as done
        redis-cli HSET "pipeline:${SESSION_ID}:phase:${PHASE_IDX}" \
            "status" "done" \
            "completed_at" "$(date -Iseconds)" >/dev/null 2>&1

        if [[ $NEXT_IDX -ge $PHASE_COUNT ]]; then
            # All phases complete
            redis-cli HSET "$CONFIG_KEY" "status" "completed" "current_phase" "$NEXT_IDX" >/dev/null 2>&1
            redis-cli SET "$CURRENT_KEY" "$NEXT_IDX" EX $TTL >/dev/null 2>&1
            echo "PIPELINE_COMPLETE: All ${PHASE_COUNT} phases done"
        else
            # Activate next phase
            redis-cli HSET "pipeline:${SESSION_ID}:phase:${NEXT_IDX}" \
                "status" "active" \
                "started_at" "$(date -Iseconds)" >/dev/null 2>&1
            redis-cli HSET "$CONFIG_KEY" "current_phase" "$NEXT_IDX" >/dev/null 2>&1
            redis-cli SET "$CURRENT_KEY" "$NEXT_IDX" EX $TTL >/dev/null 2>&1

            NEXT_NAME=$(redis-cli HGET "pipeline:${SESSION_ID}:phase:${NEXT_IDX}" "name" 2>/dev/null)
            echo "PIPELINE_ADVANCE: Phase ${PHASE_IDX} → ${NEXT_IDX} (${NEXT_NAME})"
        fi
        ;;

    handoff)
        [[ -z "$PHASE_IDX" ]] && PHASE_IDX=$(redis-cli GET "$CURRENT_KEY" 2>/dev/null)
        PHASE_KEY="pipeline:${SESSION_ID}:phase:${PHASE_IDX}"

        HANDOFF_JSON=$(jq -n \
            --arg summary "${SUMMARY:-Phase completed}" \
            --arg artifacts "${ARTIFACTS:-}" \
            --arg phase "$PHASE_IDX" \
            --arg ts "$(date -Iseconds)" \
            '{completed_work: $summary, artifacts: ($artifacts | split(",")), dod_verified: true, phase: $phase, timestamp: $ts}')

        redis-cli HSET "$PHASE_KEY" \
            "handoff_token" "$HANDOFF_JSON" \
            "artifacts" "[$(echo $ARTIFACTS | sed 's/,/","/g' | sed 's/^/"/;s/$/"/')]" \
            "dod_verified" "1" >/dev/null 2>&1

        echo "HANDOFF_TOKEN: $HANDOFF_JSON"
        ;;

    status)
        PIPELINE_STATUS=$(redis-cli HGET "$CONFIG_KEY" "status" 2>/dev/null)
        if [[ -z "$PIPELINE_STATUS" ]]; then
            echo "NO_PIPELINE: No active pipeline for session ${SESSION_ID:0:12}"
            exit 0
        fi

        PROJECT=$(redis-cli HGET "$CONFIG_KEY" "project" 2>/dev/null)
        PHASE_COUNT=$(redis-cli HGET "$CONFIG_KEY" "phase_count" 2>/dev/null)
        CURRENT=$(redis-cli GET "$CURRENT_KEY" 2>/dev/null)
        STACK=$(redis-cli HGET "$CONFIG_KEY" "stack" 2>/dev/null)

        echo "PIPELINE_STATUS: ${PIPELINE_STATUS} | Project: ${PROJECT} | Stack: ${STACK:-none}"
        echo "| Phase | Name | Status | DoD |"
        echo "|-------|------|--------|-----|"

        for ((i=0; i<PHASE_COUNT; i++)); do
            NAME=$(redis-cli HGET "pipeline:${SESSION_ID}:phase:${i}" "name" 2>/dev/null)
            STATUS=$(redis-cli HGET "pipeline:${SESSION_ID}:phase:${i}" "status" 2>/dev/null)
            DOD=$(redis-cli HGET "pipeline:${SESSION_ID}:phase:${i}" "dod_verified" 2>/dev/null)
            MARKER=""
            [[ "$i" == "$CURRENT" && "$STATUS" == "active" ]] && MARKER=" <"
            DOD_ICON=$([[ "$DOD" == "1" ]] && echo "+" || echo "-")
            echo "| ${i} | ${NAME} | ${STATUS}${MARKER} | ${DOD_ICON} |"
        done
        ;;

    regress)
        # Used by test cycle: move back to a previous phase
        [[ -z "$PHASE_IDX" ]] && echo "ERROR: --phase required" && exit 1

        redis-cli HSET "pipeline:${SESSION_ID}:phase:${PHASE_IDX}" \
            "status" "active" \
            "started_at" "$(date -Iseconds)" \
            "dod_verified" "0" >/dev/null 2>&1
        redis-cli HSET "$CONFIG_KEY" "current_phase" "$PHASE_IDX" >/dev/null 2>&1
        redis-cli SET "$CURRENT_KEY" "$PHASE_IDX" EX $TTL >/dev/null 2>&1

        NAME=$(redis-cli HGET "pipeline:${SESSION_ID}:phase:${PHASE_IDX}" "name" 2>/dev/null)
        echo "PIPELINE_REGRESS: Back to phase ${PHASE_IDX} (${NAME})"
        ;;

    reset)
        redis-cli DEL "$CONFIG_KEY" "$CURRENT_KEY" >/dev/null 2>&1
        for key in $(redis-cli --scan --pattern "pipeline:${SESSION_ID}:*" 2>/dev/null); do
            redis-cli DEL "$key" >/dev/null 2>&1
        done
        echo "PIPELINE_RESET: Cleared all pipeline data for session ${SESSION_ID:0:12}"
        ;;

    *)
        echo "Usage: pipeline-manager.sh {init|advance|handoff|status|regress|reset} [OPTIONS]"
        echo "  init    --phases frontend,content,backend,testing --project NAME [--stack React+Node]"
        echo "  advance [--phase N]"
        echo "  handoff [--phase N] --artifacts file1,file2 --summary 'what was done'"
        echo "  status"
        echo "  regress --phase N"
        echo "  reset"
        ;;
esac
