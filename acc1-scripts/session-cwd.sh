#!/bin/bash
# session-cwd.sh — per-session CWD state file helper
# Usage:
#   session-cwd.sh get <SID>             → echo CWD (or /root/claude-projects if missing)
#   session-cwd.sh set <SID> <PATH>      → write PATH atomically, validate first
#   session-cwd.sh clear <SID>           → rm state file
#   session-cwd.sh cleanup-stale         → remove /tmp/.claude-session-*.cwd older than 72h

set -euo pipefail

STATE_DIR="/tmp"
DEFAULT_ROOT="/root/claude-projects"

_state_file() {
    echo "${STATE_DIR}/.claude-session-${1}.cwd"
}

_validate_path() {
    local p="$1"
    if [ -z "$p" ]; then
        echo "[session-cwd] ERROR: empty path" >&2
        return 1
    fi
    if [[ "$p" != /root/* ]]; then
        echo "[session-cwd] ERROR: path must start with /root/ — got: $p" >&2
        return 1
    fi
    if [ ! -d "$p" ]; then
        echo "[session-cwd] ERROR: path does not exist or is not a directory: $p" >&2
        return 1
    fi
    # ADR-032: type-gate — block system directories via Redis registry
    if [[ "$p" == */claude-projects/* ]]; then
        local NAME
        NAME=$(echo "$p" | sed 's|.*/claude-projects/||' | cut -d'/' -f1)
        if [ -n "$NAME" ]; then
            local TYPE ENFORCE
            TYPE=$(redis-cli HGET "projects:registry:type" "$NAME" 2>/dev/null || echo "")
            if [ -z "$TYPE" ] && ! redis-cli PING >/dev/null 2>&1; then
                echo "[session-cwd] WARNING: Redis unavailable — blocking $NAME as precaution (ADR-032)" >&2
                return 1
            fi
            ENFORCE=$(redis-cli GET CWD_ISOLATION_ENFORCE 2>/dev/null || echo "1")
            ENFORCE="${ENFORCE:-1}"
            if [ "$TYPE" = "system" ]; then
                if [ "$ENFORCE" = "1" ]; then
                    echo "[session-cwd] BLOCKED: $NAME is system directory (ADR-032). Override: redis-cli SET CWD_ISOLATION_ENFORCE 0" >&2
                    return 1
                else
                    echo "[session-cwd] WARNING: $NAME is system directory (ADR-032) — allowed in grace period (ENFORCE=0)" >&2
                fi
            fi
        fi
    fi
    return 0
}

cmd="${1:-}"
sid="${2:-}"

case "$cmd" in
  get)
    if [ -z "$sid" ]; then
        echo "$DEFAULT_ROOT"
        exit 0
    fi
    f="$(_state_file "$sid")"
    if [ ! -f "$f" ]; then
        echo "$DEFAULT_ROOT"
        exit 0
    fi
    val=$(cat "$f" 2>/dev/null | tr -d '[:space:]')
    if [ -z "$val" ]; then
        echo "[session-cwd] WARNING: empty state file for SID=$sid, using default" >&2
        echo "$DEFAULT_ROOT"
        exit 0
    fi
    if [ ! -d "$val" ]; then
        echo "[session-cwd] WARNING: stored path no longer valid ($val), using default" >&2
        echo "$DEFAULT_ROOT"
        exit 0
    fi
    echo "$val"
    ;;

  set)
    path="${3:-}"
    if [ -z "$sid" ]; then
        echo "[session-cwd] ERROR: SID required for set" >&2
        exit 1
    fi
    if ! _validate_path "$path"; then
        exit 1
    fi
    f="$(_state_file "$sid")"
    tmp="${f}.tmp.$$"
    echo "$path" > "$tmp"
    mv -f "$tmp" "$f"
    echo "[session-cwd] set SID=$sid → $path" >&2
    ;;

  clear)
    if [ -z "$sid" ]; then
        echo "[session-cwd] ERROR: SID required for clear" >&2
        exit 1
    fi
    rm -f "$(_state_file "$sid")"
    echo "[session-cwd] cleared SID=$sid" >&2
    ;;

  cleanup-stale)
    count=$(find "${STATE_DIR}" -name '.claude-session-*.cwd' -mmin +4320 2>/dev/null | wc -l)
    find "${STATE_DIR}" -name '.claude-session-*.cwd' -mmin +4320 -delete 2>/dev/null || true
    echo "[session-cwd] cleanup-stale: removed $count files older than 72h" >&2
    ;;

  *)
    echo "Usage: session-cwd.sh {get|set|clear|cleanup-stale} [SID] [PATH]" >&2
    exit 1
    ;;
esac
