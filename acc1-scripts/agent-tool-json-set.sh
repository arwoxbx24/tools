#!/usr/bin/env bash
# agent-tool-json-set.sh — Safely set a key in a JSON file using jq
# Part of agent-cli-tools-package (ADR-007)
#
# Usage:
#   agent-tool-json-set.sh FILE '.key.path' 'value' [--type string|number|bool]
#
# Atomic: write to tmp → validate → backup original → mv tmp to target
# Replaces: python3 -c "import json..." field modification one-liners

set -euo pipefail

TOOL_NAME="agent-tool-json-set.sh"

# --- Help ---
usage() {
  cat <<EOF
Usage: $TOOL_NAME <file> <jq_path> <value> [--type string|number|bool]

Set a key in a JSON file atomically using jq.

Arguments:
  file      Path to JSON file to modify (must exist)
  jq_path   jq key path to set (e.g. '.model', '.redis.db', '.flags.enabled')
  value     New value to assign

Options:
  --type string   Treat value as a JSON string (default)
  --type number   Treat value as a JSON number
  --type bool     Treat value as a JSON boolean (true/false)
  --type raw      Pass value directly as a jq expression (advanced)
  -h, --help      Show this help message

Behavior:
  1. Validates input JSON
  2. Writes modified JSON to a temp file
  3. Validates temp file output
  4. Backs up original to FILE.bak
  5. Atomically moves temp file to FILE

Examples:
  # Set string value
  $TOOL_NAME settings.json '.model' 'claude-opus-4'

  # Set number value
  $TOOL_NAME config.json '.redis.db' '2' --type number

  # Set boolean value
  $TOOL_NAME config.json '.features.enabled' 'true' --type bool

  # Set nested key (creates path if supported by jq)
  $TOOL_NAME config.json '.server.port' '8080' --type number
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

if [[ $# -lt 3 ]]; then
  echo "$TOOL_NAME: error: requires at least 3 arguments: FILE, JQ_PATH, VALUE" >&2
  usage >&2
  exit 1
fi

FILE="$1"
JQ_PATH="$2"
VALUE="$3"
VALUE_TYPE="string"  # default

# Parse optional --type flag
shift 3
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      if [[ $# -lt 2 ]]; then
        echo "$TOOL_NAME: error: --type requires an argument (string|number|bool|raw)" >&2
        exit 1
      fi
      VALUE_TYPE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "$TOOL_NAME: error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

# --- Dependency check ---
if ! command -v jq &>/dev/null; then
  echo "$TOOL_NAME: error: jq is not installed. Install with: apt-get install jq" >&2
  exit 1
fi

# --- File existence check ---
if [[ ! -f "$FILE" ]]; then
  echo "$TOOL_NAME: error: file not found: $FILE" >&2
  exit 1
fi

# --- Validate input JSON ---
if ! jq empty "$FILE" 2>/dev/null; then
  echo "$TOOL_NAME: error: invalid JSON in file: $FILE" >&2
  exit 1
fi

# --- Build jq expression based on type ---
case "$VALUE_TYPE" in
  string)
    JQ_EXPR="${JQ_PATH} = \$newval"
    JQ_ARGS=(--arg newval "$VALUE")
    ;;
  number)
    # Validate it's actually a number
    if ! echo "$VALUE" | grep -qE '^-?[0-9]+(\.[0-9]+)?$'; then
      echo "$TOOL_NAME: error: value '$VALUE' is not a valid number" >&2
      exit 1
    fi
    JQ_EXPR="${JQ_PATH} = (\$newval | tonumber)"
    JQ_ARGS=(--arg newval "$VALUE")
    ;;
  bool)
    # Normalize to true/false
    case "$VALUE" in
      true|True|TRUE|1|yes|Yes|YES)
        BOOL_VAL="true"
        ;;
      false|False|FALSE|0|no|No|NO)
        BOOL_VAL="false"
        ;;
      *)
        echo "$TOOL_NAME: error: value '$VALUE' is not a valid boolean (use true/false)" >&2
        exit 1
        ;;
    esac
    JQ_EXPR="${JQ_PATH} = ${BOOL_VAL}"
    JQ_ARGS=()
    ;;
  raw)
    # Value passed directly as jq expression — user responsibility
    JQ_EXPR="${JQ_PATH} = (${VALUE})"
    JQ_ARGS=()
    ;;
  *)
    echo "$TOOL_NAME: error: unknown type '$VALUE_TYPE'. Use: string, number, bool, raw" >&2
    exit 1
    ;;
esac

# --- Temp file ---
TMP_FILE="$(dirname "$FILE")/.$(basename "$FILE").tmp.$$"
trap 'rm -f "$TMP_FILE"' EXIT

# --- Apply change to temp file ---
if ! jq "${JQ_ARGS[@]+"${JQ_ARGS[@]}"}" "$JQ_EXPR" "$FILE" > "$TMP_FILE" 2>/tmp/agent-tool-json-set-err.$$; then
  ERR=$(cat /tmp/agent-tool-json-set-err.$$ 2>/dev/null)
  rm -f /tmp/agent-tool-json-set-err.$$
  echo "$TOOL_NAME: error: jq failed: $ERR" >&2
  exit 1
fi
rm -f /tmp/agent-tool-json-set-err.$$

# --- Validate output JSON ---
if ! jq empty "$TMP_FILE" 2>/dev/null; then
  echo "$TOOL_NAME: error: output validation failed — result is not valid JSON" >&2
  exit 1
fi

# --- Backup original ---
BAK_FILE="${FILE}.bak"
cp "$FILE" "$BAK_FILE"

# --- Atomic move ---
mv "$TMP_FILE" "$FILE"

echo "$TOOL_NAME: ok — set ${JQ_PATH} in ${FILE} (backup: ${BAK_FILE})"
