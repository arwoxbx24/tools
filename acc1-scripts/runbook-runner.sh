#!/bin/bash
# runbook-runner.sh — Execute YAML infrastructure runbook templates
# Usage: runbook-runner.sh <template.yaml> [VAR=value ...] [--dry-run]
# V_RUNBOOK: Authorized infrastructure automation runner
set -euo pipefail

export RUNBOOK_RUNNER_PID=$$
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ACTION_DIR="$SCRIPT_DIR/actions"
LOG_DIR="/root/workspaces/tools/acc1-scripts/data/runbook-logs"
SECRETS_DIR="/root/workspaces/secrets/services"

# Parse args
TEMPLATE="${1:?Usage: runbook-runner.sh <template.yaml> [VAR=value ...] [--dry-run]}"
shift
DRY_RUN=false
declare -A VARS

for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    elif [[ "$arg" == *"="* ]]; then
        key="${arg%%=*}"
        val="${arg#*=}"
        VARS["$key"]="$val"
    fi
done

# Parse YAML template
mkdir -p "$LOG_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RUNBOOK_NAME=$(basename "$TEMPLATE" .yaml)
LOG_FILE="$LOG_DIR/${RUNBOOK_NAME}-${TIMESTAMP}.log"

echo "=== Runbook: $RUNBOOK_NAME ===" | tee "$LOG_FILE"
echo "Template: $TEMPLATE" | tee -a "$LOG_FILE"
echo "Dry-run: $DRY_RUN" | tee -a "$LOG_FILE"
echo "Variables: ${!VARS[*]}" | tee -a "$LOG_FILE"
echo "---" | tee -a "$LOG_FILE"

# Parse steps from YAML using python3
STEPS_JSON=$(python3 "$SCRIPT_DIR/parse-runbook.py" "$TEMPLATE" 2>/dev/null)
if [[ -z "$STEPS_JSON" ]]; then
    echo "ERROR: Failed to parse template $TEMPLATE" | tee -a "$LOG_FILE"
    exit 1
fi

STEP_COUNT=$(echo "$STEPS_JSON" | jq '. | length')
echo "Steps: $STEP_COUNT" | tee -a "$LOG_FILE"

PREV_RESULT=""
for i in $(seq 0 $((STEP_COUNT - 1))); do
    STEP_NAME=$(echo "$STEPS_JSON" | jq -r ".[$i].name")
    ACTION=$(echo "$STEPS_JSON" | jq -r ".[$i].action")
    PARAMS=$(echo "$STEPS_JSON" | jq -r ".[$i].params // {}")

    # Substitute variables in params
    EXPANDED_PARAMS="$PARAMS"
    for key in "${!VARS[@]}"; do
        EXPANDED_PARAMS=$(echo "$EXPANDED_PARAMS" | sed "s/\${$key}/${VARS[$key]}/g")
    done
    # Substitute PREV_STEP_RESULT
    EXPANDED_PARAMS=$(echo "$EXPANDED_PARAMS" | sed "s/\${PREV_STEP_RESULT}/$PREV_RESULT/g")

    echo "" | tee -a "$LOG_FILE"
    echo "[$((i+1))/$STEP_COUNT] $STEP_NAME (action: $ACTION)" | tee -a "$LOG_FILE"
    echo "  Params: $EXPANDED_PARAMS" | tee -a "$LOG_FILE"

    if $DRY_RUN; then
        echo "  [DRY-RUN] Would execute: $ACTION_DIR/${ACTION}.sh" | tee -a "$LOG_FILE"
        continue
    fi

    # Execute action handler
    HANDLER="$ACTION_DIR/${ACTION}.sh"
    if [[ ! -x "$HANDLER" ]]; then
        echo "  ERROR: Handler not found: $HANDLER" | tee -a "$LOG_FILE"
        exit 1
    fi

    RESULT=$("$HANDLER" "$EXPANDED_PARAMS" 2>&1) || {
        EXIT_CODE=$?
        if [[ $EXIT_CODE -eq 2 ]]; then
            echo "  SKIP: Already exists (idempotent)" | tee -a "$LOG_FILE"
        else
            echo "  FAILED (exit $EXIT_CODE): $RESULT" | tee -a "$LOG_FILE"
            echo "=== RUNBOOK FAILED at step $((i+1)) ===" | tee -a "$LOG_FILE"
            exit 1
        fi
    }

    PREV_RESULT=$(echo "$RESULT" | tail -1)
    echo "  OK: $PREV_RESULT" | tee -a "$LOG_FILE"
done

echo "" | tee -a "$LOG_FILE"
echo "=== RUNBOOK COMPLETE ===" | tee -a "$LOG_FILE"
echo "Log: $LOG_FILE"
