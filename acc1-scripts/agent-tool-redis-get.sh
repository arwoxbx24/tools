#!/bin/bash
# agent-tool-redis-get.sh — structured Redis query tool for agents
# ADR: docs/adr/ADR-007-agent-cli-tools-package.md
#
# Usage: agent-tool-redis-get.sh KEY [--type auto|string|hash|list|set|zset] [--format json|raw] [--db N]
#
# Supports: string, hash, list, set, zset
# Auto-detects key type when --type auto (default)
# Outputs raw value or JSON-encoded result
# Exit 0 = success; 1 = error (key missing, conn error, wrong type)

set -euo pipefail

# ─── Defaults ────────────────────────────────────────────────────────────────
KEY=""
TYPE="auto"
FORMAT="raw"
DB=0
REDIS_HOST="${REDIS_HOST:-127.0.0.1}"
REDIS_PORT="${REDIS_PORT:-6379}"

# ─── Help ─────────────────────────────────────────────────────────────────────
usage() {
  cat <<'EOF'
Usage:
  agent-tool-redis-get.sh KEY [OPTIONS]

Arguments:
  KEY                  Redis key to query

Options:
  --type  auto|string|hash|list|set|zset
                       Key type. Default: auto (detect via TYPE command)
  --format  json|raw   Output format. Default: raw
  --db  N              Redis database number. Default: 0
  --host  HOST         Redis host. Default: 127.0.0.1 (or $REDIS_HOST)
  --port  PORT         Redis port. Default: 6379 (or $REDIS_PORT)
  -h, --help           Show this help

Output:
  string  → raw value or JSON string
  hash    → key=value lines (raw) or {"k":"v",...} (json)
  list    → newline-separated items (raw) or JSON array
  set     → newline-separated members (raw) or JSON array
  zset    → "member score" lines (raw) or [{"member":"...","score":N},...] (json)

Exit codes:
  0   success
  1   key not found, Redis unavailable, or unsupported type

Examples:
  agent-tool-redis-get.sh session:latest
  agent-tool-redis-get.sh acs:stats:rule:V109 --db 2 --format json
  agent-tool-redis-get.sh topic:index:feat --type set
  agent-tool-redis-get.sh pipeline:abc:phase:0 --format json --db 0
EOF
}

# ─── Argument parsing ─────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

# First positional = KEY (unless first arg is a flag)
if [[ "$1" != --* && "$1" != "-h" ]]; then
  KEY="$1"
  shift
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      TYPE="${2:?--type requires a value}"
      shift 2
      ;;
    --format)
      FORMAT="${2:?--format requires a value}"
      shift 2
      ;;
    --db)
      DB="${2:?--db requires a value}"
      shift 2
      ;;
    --host)
      REDIS_HOST="${2:?--host requires a value}"
      shift 2
      ;;
    --port)
      REDIS_PORT="${2:?--port requires a value}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$KEY" ]]; then
  echo "ERROR: KEY argument is required" >&2
  usage >&2
  exit 1
fi

# Validate --format
case "$FORMAT" in
  json|raw) ;;
  *)
    echo "ERROR: --format must be json or raw (got: $FORMAT)" >&2
    exit 1
    ;;
esac

# Validate --type
case "$TYPE" in
  auto|string|hash|list|set|zset) ;;
  *)
    echo "ERROR: --type must be auto|string|hash|list|set|zset (got: $TYPE)" >&2
    exit 1
    ;;
esac

# ─── Redis connectivity ───────────────────────────────────────────────────────
rcli() {
  redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" -n "$DB" "$@" 2>/dev/null
}

PING=$(redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping 2>/dev/null || true)
if [[ "$PING" != "PONG" ]]; then
  echo "REDIS_UNAVAILABLE" >&2
  exit 1
fi

# ─── Key existence check ──────────────────────────────────────────────────────
EXISTS=$(rcli exists "$KEY")
if [[ "$EXISTS" == "0" ]]; then
  echo "NULL" >&2
  exit 1
fi

# ─── Type detection ───────────────────────────────────────────────────────────
if [[ "$TYPE" == "auto" ]]; then
  TYPE=$(rcli type "$KEY")
  # redis-cli returns "none" if key missing (race), "string", "hash", "list", "set", "zset"
  if [[ "$TYPE" == "none" ]]; then
    echo "NULL" >&2
    exit 1
  fi
fi

# ─── Helpers: JSON escaping ───────────────────────────────────────────────────
# Escape a string for JSON using printf + sed (no jq dependency for safety)
# We use jq if available for proper escaping, else fallback to basic sed
json_str() {
  local val="$1"
  if command -v jq &>/dev/null; then
    # jq -Rs adds trailing newline — strip it with printf %s
    printf '%s' "$(printf '%s' "$val" | jq -Rs '.')"
  else
    # Basic escaping: backslash, double-quote, control chars
    printf '"%s"' "$(printf '%s' "$val" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')"
  fi
}

# ─── Output by type ───────────────────────────────────────────────────────────
case "$TYPE" in

  string)
    VAL=$(rcli get "$KEY")
    if [[ "$FORMAT" == "json" ]]; then
      json_str "$VAL"
    else
      printf '%s\n' "$VAL"
    fi
    ;;

  hash)
    # hgetall returns flat list: field\nvalue\nfield\nvalue...
    mapfile -t PAIRS < <(rcli hgetall "$KEY")
    if [[ "$FORMAT" == "json" ]]; then
      # Build JSON object
      printf '{'
      FIRST=1
      i=0
      while [[ $i -lt ${#PAIRS[@]} ]]; do
        FIELD="${PAIRS[$i]}"
        VALUE="${PAIRS[$((i+1))]:-}"
        if [[ $FIRST -eq 0 ]]; then printf ','; fi
        FIRST=0
        printf '%s:%s' "$(json_str "$FIELD")" "$(json_str "$VALUE")"
        i=$((i+2))
      done
      printf '}\n'
    else
      i=0
      while [[ $i -lt ${#PAIRS[@]} ]]; do
        FIELD="${PAIRS[$i]}"
        VALUE="${PAIRS[$((i+1))]:-}"
        printf '%s=%s\n' "$FIELD" "$VALUE"
        i=$((i+2))
      done
    fi
    ;;

  list)
    mapfile -t ITEMS < <(rcli lrange "$KEY" 0 -1)
    if [[ "$FORMAT" == "json" ]]; then
      printf '['
      FIRST=1
      for ITEM in "${ITEMS[@]}"; do
        if [[ $FIRST -eq 0 ]]; then printf ','; fi
        FIRST=0
        json_str "$ITEM"
      done
      printf ']\n'
    else
      for ITEM in "${ITEMS[@]}"; do
        printf '%s\n' "$ITEM"
      done
    fi
    ;;

  set)
    mapfile -t MEMBERS < <(rcli smembers "$KEY")
    if [[ "$FORMAT" == "json" ]]; then
      printf '['
      FIRST=1
      for M in "${MEMBERS[@]}"; do
        if [[ $FIRST -eq 0 ]]; then printf ','; fi
        FIRST=0
        json_str "$M"
      done
      printf ']\n'
    else
      for M in "${MEMBERS[@]}"; do
        printf '%s\n' "$M"
      done
    fi
    ;;

  zset)
    # zrange with scores: member score member score ...
    mapfile -t ZPAIRS < <(rcli zrange "$KEY" 0 -1 withscores)
    if [[ "$FORMAT" == "json" ]]; then
      printf '['
      FIRST=1
      i=0
      while [[ $i -lt ${#ZPAIRS[@]} ]]; do
        MEMBER="${ZPAIRS[$i]}"
        SCORE="${ZPAIRS[$((i+1))]:-0}"
        if [[ $FIRST -eq 0 ]]; then printf ','; fi
        FIRST=0
        printf '{"member":%s,"score":%s}' "$(json_str "$MEMBER")" "$SCORE"
        i=$((i+2))
      done
      printf ']\n'
    else
      i=0
      while [[ $i -lt ${#ZPAIRS[@]} ]]; do
        MEMBER="${ZPAIRS[$i]}"
        SCORE="${ZPAIRS[$((i+1))]:-0}"
        printf '%s %s\n' "$MEMBER" "$SCORE"
        i=$((i+2))
      done
    fi
    ;;

  *)
    echo "ERROR: unsupported Redis type '$TYPE' for key '$KEY'" >&2
    exit 1
    ;;
esac
