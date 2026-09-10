#!/usr/bin/env bash
set -euo pipefail

JSON_FILE="/tmp/registry-classification.json"
REDIS_KEY="projects:registry:type"

usage() {
  cat <<EOF
Usage: $(basename "$0") [--dry-run | --apply] [--file PATH]

Populates Redis hash '$REDIS_KEY' from a classification JSON file.

Options:
  --dry-run   Show what would be written (default, safe mode)
  --apply     Actually write to Redis
  --file PATH Path to JSON file (default: $JSON_FILE)
  --help      Show this help

JSON format: {"name": {"path": "...", "type": "client|system", "reason": "..."}}

The script is idempotent — repeated runs do not break existing data.
Does NOT touch 'projects:registry' (main hash).
EOF
  exit 0
}

MODE="dry-run"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) MODE="dry-run" ;;
    --apply)   MODE="apply" ;;
    --file)    shift; JSON_FILE="$1" ;;
    --help|-h) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

if [[ ! -f "$JSON_FILE" ]]; then
  echo "ERROR: JSON file not found: $JSON_FILE" >&2
  echo "Create it first or specify --file PATH" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not installed" >&2
  exit 1
fi

if ! command -v redis-cli &>/dev/null; then
  echo "ERROR: redis-cli is required but not installed" >&2
  exit 1
fi

echo "Mode: $MODE"
echo "Source: $JSON_FILE"
echo "Target key: $REDIS_KEY"
echo "---"

count=0
errors=0

while IFS= read -r name; do
  type_val=$(jq -r --arg n "$name" '.[$n].type' "$JSON_FILE")
  reason=$(jq -r --arg n "$name" '.[$n].reason' "$JSON_FILE")

  if [[ -z "$type_val" || "$type_val" == "null" ]]; then
    echo "SKIP [$name] — missing type" >&2
    ((errors++)) || true
    continue
  fi

  if [[ "$MODE" == "dry-run" ]]; then
    echo "DRY-RUN: HSET $REDIS_KEY $name $type_val  # $reason"
  else
    redis-cli HSET "$REDIS_KEY" "$name" "$type_val" > /dev/null
    echo "SET: $name = $type_val"
  fi
  ((count++)) || true
done < <(jq -r 'keys[]' "$JSON_FILE")

echo "---"
echo "Processed: $count entries, errors: $errors"

if [[ "$MODE" == "dry-run" ]]; then
  echo "Run with --apply to write to Redis."
fi
