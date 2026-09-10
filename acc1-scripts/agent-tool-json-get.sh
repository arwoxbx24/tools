#!/usr/bin/env bash
# agent-tool-json-get.sh — Extract a field from JSON using jq
# Part of agent-cli-tools-package (ADR-007)
#
# Usage:
#   agent-tool-json-get.sh <jq_path> [file|-]
#   echo '{"key":"val"}' | agent-tool-json-get.sh '.key'
#
# Replaces: python3 -c "import json..." field extraction one-liners

set -euo pipefail

TOOL_NAME="agent-tool-json-get.sh"

# --- Help ---
usage() {
  cat <<EOF
Usage: $TOOL_NAME <jq_path> [file|-]

Extract a field or expression from a JSON file or stdin using jq.

Arguments:
  jq_path   jq filter expression (e.g. '.model', '.redis.db', '.items[0]')
  file      Path to JSON file. Use '-' or omit to read from stdin.

Options:
  -h, --help   Show this help message

Output:
  Raw scalar value (no surrounding quotes for strings).
  Empty string + exit 0 if key is missing and no default given.
  Error message to stderr + exit 1 on invalid JSON or file not found.

Examples:
  # From file
  $TOOL_NAME '.model' /root/workspaces/tools/acc1-scripts/settings.json

  # From stdin
  echo '{"status":"ok","count":3}' | $TOOL_NAME '.count'

  # Nested path
  cat .claude.json | $TOOL_NAME '.numProfileStartups' -

  # Missing key with default (jq syntax)
  $TOOL_NAME '.missing // "N/A"' file.json

  # Array element
  $TOOL_NAME '.items[0].name' data.json
EOF
}

# --- Arg parsing ---
if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

case "$1" in
  -h|--help)
    usage
    exit 0
    ;;
esac

JQ_PATH="$1"
FILE="${2:--}"   # default to stdin if no second arg

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo "$TOOL_NAME: error: jq is not installed. Install with: apt-get install jq" >&2
  exit 1
fi

# --- File existence check ---
if [[ "$FILE" != "-" && ! -f "$FILE" ]]; then
  echo "$TOOL_NAME: error: file not found: $FILE" >&2
  exit 1
fi

# --- Execute ---
# -r = raw output (no quotes around strings)
# errors from jq go to stderr automatically
if ! jq -r "$JQ_PATH" "${FILE}" 2>/tmp/agent-tool-json-get-err.$$; then
  ERR=$(cat /tmp/agent-tool-json-get-err.$$ 2>/dev/null)
  rm -f /tmp/agent-tool-json-get-err.$$
  echo "$TOOL_NAME: error: $ERR" >&2
  exit 1
fi

rm -f /tmp/agent-tool-json-get-err.$$
