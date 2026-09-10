#!/bin/bash
# detect-model.sh — detects running Claude model
# Source this: source detect-model.sh
# Result: DETECTED_MODEL variable (opus|sonnet|haiku)

DETECTED_MODEL="sonnet"  # safe default

# Priority 1: explicit env var
if [[ -n "${CLAUDE_MODEL:-}" ]]; then
    case "$CLAUDE_MODEL" in
        *opus*) DETECTED_MODEL="opus" ;;
        *haiku*) DETECTED_MODEL="haiku" ;;
        *) DETECTED_MODEL="sonnet" ;;
    esac
    return 0 2>/dev/null || true
fi

# Priority 2: check process args for --model flag
_CLAUDE_PID=$(timeout 0.1 pgrep -f "node.*claude" 2>/dev/null | head -1)
if [[ -n "$_CLAUDE_PID" ]]; then
    _PROC_ARGS=$(cat /proc/${_CLAUDE_PID}/cmdline 2>/dev/null | tr '\0' ' ')
    if echo "$_PROC_ARGS" | grep -qi "opus"; then
        DETECTED_MODEL="opus"
        return 0 2>/dev/null || true
    elif echo "$_PROC_ARGS" | grep -qi "haiku"; then
        DETECTED_MODEL="haiku"
        return 0 2>/dev/null || true
    fi
fi

# Priority 3: settings.json model field
_SETTINGS="/root/workspaces/tools/acc1-scripts/settings.json"
if [[ -f "$_SETTINGS" ]]; then
    _MODEL=$(python3 -c "import json; print(json.load(open('$_SETTINGS')).get('model','sonnet'))" 2>/dev/null)
    case "${_MODEL:-}" in
        *opus*) DETECTED_MODEL="opus" ;;
        *haiku*) DETECTED_MODEL="haiku" ;;
        *) DETECTED_MODEL="sonnet" ;;
    esac
fi
