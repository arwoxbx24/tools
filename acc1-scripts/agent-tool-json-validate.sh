#!/usr/bin/env bash
# agent-tool-json-validate.sh — Validate JSON using jq (pure jq, no python3)
# Part of agent-cli-tools-package (ADR-007)
#
# Usage:
#   agent-tool-json-validate.sh [--pretty] [FILE]
#   echo '{"key":"val"}' | agent-tool-json-validate.sh [--pretty]
#
# Replaces: python3 -m json.tool patterns

set -uo pipefail

TOOL_NAME="agent-tool-json-validate.sh"
PRETTY=0
FILE="-"

# --- Help ---
usage() {
  cat <<EOF
Usage: $TOOL_NAME [--pretty] [file|-]

Validate a JSON file or stdin using jq.

Arguments:
  file      Path to JSON file. Use '-' or omit to read from stdin.

Options:
  --pretty  Also print formatted JSON output after validation
  -h, --help   Show this help message

Output:
  VALID: <N> keys/elements — on success
  INVALID: <error line from jq> — on failure (exit 1)

Exit codes:
  0 = valid JSON
  1 = invalid JSON or file not found

Examples:
  # Validate a file
  $TOOL_NAME /root/workspaces/tools/acc1-scripts/settings.json

  # Validate stdin
  echo '{"status":"ok","count":3}' | $TOOL_NAME

  # Validate and pretty-print
  $TOOL_NAME --pretty config.json

  # Detect broken JSON
  echo '{"broken":}' | $TOOL_NAME
EOF
}

# --- Arg parsing ---
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --pretty)
      PRETTY=1
      ;;
    -*)
      echo "$TOOL_NAME: error: unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
    *)
      FILE="$arg"
      ;;
  esac
done

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

# --- Read input into temp file to allow two passes (validate + count) ---
TMPFILE=$(mktemp /tmp/agent-tool-json-validate.XXXXXX)
trap 'rm -f "$TMPFILE"' EXIT

if [[ "$FILE" == "-" ]]; then
  cat > "$TMPFILE"
else
  cp "$FILE" "$TMPFILE"
fi

# --- Validate JSON ---
ERRFILE=$(mktemp /tmp/agent-tool-json-validate-err.XXXXXX)
trap 'rm -f "$TMPFILE" "$ERRFILE"' EXIT

if ! jq empty "$TMPFILE" 2>"$ERRFILE"; then
  ERR=$(cat "$ERRFILE")
  echo "INVALID: ${ERR}" >&2
  exit 1
fi

# --- Count top-level keys or array elements ---
# Use jq: if object → count keys; if array → length; else → 1
COUNT=$(jq 'if type == "object" then keys | length
            elif type == "array" then length
            else 1
            end' "$TMPFILE" 2>/dev/null || echo "?")

TYPE=$(jq -r 'type' "$TMPFILE" 2>/dev/null || echo "unknown")

case "$TYPE" in
  object)  LABEL="keys" ;;
  array)   LABEL="elements" ;;
  *)       LABEL="value" ;;
esac

echo "VALID: ${COUNT} ${LABEL}"

# --- Pretty print if requested ---
if [[ "$PRETTY" -eq 1 ]]; then
  jq '.' "$TMPFILE"
fi

exit 0
