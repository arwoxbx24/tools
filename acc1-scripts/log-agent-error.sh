#!/bin/bash
# Script: log-agent-error.sh
# Purpose: Log errors from junior agents to unified error registry
# Usage: ./log-agent-error.sh <agent_name> <error_type> <error_message> <context>

set -euo pipefail

# Configuration
LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/agent-errors.log"
LOG_DIR="$(dirname "$LOG_FILE")"

# Ensure logs directory exists
mkdir -p "$LOG_DIR"

# Validate arguments
if [ $# -lt 4 ]; then
    echo "Usage: $0 <agent_name> <error_type> <error_message> <context>" >&2
    echo "Example: $0 haiku api_error 'Rate limit exceeded' embeddings" >&2
    exit 1
fi

# Parameters
AGENT_NAME="$1"
ERROR_TYPE="$2"
ERROR_MESSAGE="$3"
CONTEXT="$4"

# Get ISO 8601 timestamp with UTC timezone
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Escape special characters for JSON
escape_json() {
    local input="$1"
    # Escape backslashes first, then quotes, then newlines, tabs, and other control chars
    echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g; s/\r/\\r/g' | awk '{printf "%s\\n", $0}' | sed '$ s/\\n$//'
}

AGENT_ESCAPED=$(escape_json "$AGENT_NAME")
TYPE_ESCAPED=$(escape_json "$ERROR_TYPE")
MSG_ESCAPED=$(escape_json "$ERROR_MESSAGE")
CONTEXT_ESCAPED=$(escape_json "$CONTEXT")

# Create JSON log entry
LOG_ENTRY="{\"ts\":\"$TIMESTAMP\",\"agent\":\"$AGENT_ESCAPED\",\"type\":\"$TYPE_ESCAPED\",\"msg\":\"$MSG_ESCAPED\",\"context\":\"$CONTEXT_ESCAPED\"}"

# Append to log file (create if doesn't exist)
echo "$LOG_ENTRY" >> "$LOG_FILE"

# Output confirmation to stderr (so stdout can be used in pipelines)
echo "Error logged: $AGENT_NAME ($ERROR_TYPE) at $TIMESTAMP" >&2

# Return success
exit 0
