#!/bin/bash
# Agent Hierarchy Enforcement Hook
#
# Usage: check-agent-hierarchy.sh <model> "<command>"
# Exit codes:
#   0 = allowed
#   2 = blocked (hard stop)
#
# Integration: Call from delegate-task.sh or pre-exec hooks

AGENT_MODEL="${1:-unknown}"
COMMAND="${2:-}"
PROJECT_DIR="/root/claude-projects/bitrix-migration"
HIERARCHY_DOC="$PROJECT_DIR/docs/reference/AGENT_HIERARCHY.md"

# Only check if working in bitrix-migration
if [[ "$COMMAND" != *"bitrix-migration"* ]]; then
    exit 0
fi

# Function to block and report
block_action() {
    local reason="$1"
    echo "⛔ BLOCKING: $reason"
    echo "➡️ Read: $HIERARCHY_DOC"
    echo "Agent: $AGENT_MODEL | Command: $COMMAND"
    exit 2
}

# JUNIOR (Haiku) restrictions
if [[ "$AGENT_MODEL" == "haiku" ]]; then
    # Only allow: npm scripts, grep, cat, ls, Read tool
    if [[ "$COMMAND" != *"npm run"* && \
          "$COMMAND" != *"grep"* && \
          "$COMMAND" != *"cat"* && \
          "$COMMAND" != *"ls"* && \
          "$COMMAND" != *"head"* && \
          "$COMMAND" != *"tail"* ]]; then
        block_action "Haiku (JUNIOR) can only use npm scripts and search commands!"
    fi

    # Block any migration/clean/generate operations
    if [[ "$COMMAND" == *"npm run migrate"* || \
          "$COMMAND" == *"npm run clean"* || \
          "$COMMAND" == *"npm run generate"* ]]; then
        block_action "Haiku (JUNIOR) cannot run migration/clean/generate commands!"
    fi
fi

# DEPUTY (Sonnet) restrictions
if [[ "$AGENT_MODEL" == "sonnet" ]]; then
    # Block direct node commands
    if [[ "$COMMAND" == *"node src/"* || "$COMMAND" == *"node ./src/"* ]]; then
        block_action "Sonnet (DEPUTY) cannot run direct node commands - use npm scripts!"
    fi

    # Block .env modifications
    if [[ "$COMMAND" == *".env"* && ( "$COMMAND" == *"echo"* || "$COMMAND" == *">"* ) ]]; then
        block_action "Sonnet (DEPUTY) cannot modify .env files!"
    fi

    # Block webhook URLs in commands
    if [[ "$COMMAND" == *"bitrix24.ru/rest/"* || "$COMMAND" == *"bx24dev.ru/rest/"* ]]; then
        block_action "Sonnet (DEPUTY) cannot use webhook URLs in commands!"
    fi
fi

# ARCHITECT (Opus) - no restrictions for bitrix-migration
if [[ "$AGENT_MODEL" == "opus" ]]; then
    exit 0
fi

# Unknown model - warn but allow
if [[ "$AGENT_MODEL" == "unknown" ]]; then
    echo "⚠️ WARNING: Unknown agent model - cannot verify hierarchy compliance"
    exit 0
fi

exit 0
