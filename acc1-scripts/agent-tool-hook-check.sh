#!/bin/bash
# ============================================================================
# agent-tool-hook-check.sh
# PURPOSE: Quick validation of a single hook file after editing.
#          Checks: bash syntax, sourced libs exist, registration in settings.json
# USAGE:   agent-tool-hook-check.sh HOOK_FILE [--full]
#          --full  also runs shellcheck (if available) and prints hook command
# EXIT:    0 = PASS, 1 = FAIL
# ============================================================================

set -euo pipefail

HOOKS_DIR="/root/workspaces/tools/acc1-scripts/hooks"
SETTINGS="/root/workspaces/tools/acc1-scripts/settings.json"
SCRIPTS_DIR="/root/workspaces/tools/acc1-scripts/scripts"

# ── colour helpers ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

pass()  { echo -e "${GREEN}[PASS]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; FAILURES=$((FAILURES + 1)); }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
title() { echo -e "\n${BOLD}=== $* ===${NC}"; }

FAILURES=0
FULL=false

# ── argument parsing ─────────────────────────────────────────────────────────
HOOK_FILE=""
for arg in "$@"; do
    case "$arg" in
        --full) FULL=true ;;
        -*)     echo "Unknown flag: $arg" >&2; exit 1 ;;
        *)      HOOK_FILE="$arg" ;;
    esac
done

if [ -z "$HOOK_FILE" ]; then
    echo "Usage: $(basename "$0") HOOK_FILE [--full]" >&2
    echo "  HOOK_FILE  path or basename (e.g. enforce-v254-task-before-agent.sh)" >&2
    exit 1
fi

# Resolve full path: accept absolute path, hooks/ basename, or scripts/ basename
if [ -f "$HOOK_FILE" ]; then
    ABS_PATH="$(realpath "$HOOK_FILE")"
elif [ -f "${HOOKS_DIR}/${HOOK_FILE}" ]; then
    ABS_PATH="${HOOKS_DIR}/${HOOK_FILE}"
elif [ -f "${SCRIPTS_DIR}/${HOOK_FILE}" ]; then
    ABS_PATH="${SCRIPTS_DIR}/${HOOK_FILE}"
else
    echo -e "${RED}[ERROR]${NC} File not found: $HOOK_FILE" >&2
    exit 1
fi

BASENAME="$(basename "$ABS_PATH")"

title "Hook Check: $BASENAME"
info "Path: $ABS_PATH"

# ── CHECK 1: file exists and is readable ─────────────────────────────────────
title "1. File"
if [ -f "$ABS_PATH" ] && [ -r "$ABS_PATH" ]; then
    pass "File exists and readable"
else
    fail "File missing or not readable"
fi

# ── CHECK 2: bash syntax ─────────────────────────────────────────────────────
title "2. Bash Syntax (bash -n)"
SYNTAX_ERR=$(bash -n "$ABS_PATH" 2>&1)
if [ $? -eq 0 ]; then
    pass "Syntax OK"
else
    fail "Syntax error:\n    $SYNTAX_ERR"
fi

# ── CHECK 3: sourced libraries exist ─────────────────────────────────────────
title "3. Sourced Libraries"
# Extract all source / . lines; resolve relative to the hook's directory
HOOK_DIR="$(dirname "$ABS_PATH")"
SOURCE_LINES=$(grep -E '^\s*(\.|source)\s+' "$ABS_PATH" 2>/dev/null || true)

if [ -z "$SOURCE_LINES" ]; then
    info "No source/. statements found"
else
    while IFS= read -r line; do
        # Extract the path after source/. — handle variable expansion like $(dirname "$0")/lib/foo.sh
        RAW=$(echo "$line" | sed -E 's/^\s*(\.|source)\s+//')

        # Strip trailing shell operators: 2>/dev/null, || true, && ..., ; ...
        RAW_CLEAN=$(echo "$RAW" | sed -E 's/[[:space:]]+(2>[^[:space:]]+|[|][|][[:space:]]+[a-z]+|&&.*|;.*)//g')

        # Normalise: replace $(dirname "$0"), $(dirname "${BASH_SOURCE[0]}") with actual hook dir
        RESOLVED=$(echo "$RAW_CLEAN" | sed \
            -e "s|\$(dirname \"\$0\")|${HOOK_DIR}|g" \
            -e "s|\$(dirname \"\${BASH_SOURCE\[0\]}\"|${HOOK_DIR}|g" \
            -e "s|\$(dirname \${BASH_SOURCE\[0\]})|${HOOK_DIR}|g" \
            -e "s|\"\$HOME\"|${HOME}|g" \
            -e "s|\$HOME|${HOME}|g" \
            -e 's/^["'"'"']//; s/["'"'"']$//' \
            | tr -d '"' | xargs 2>/dev/null || echo "")

        # Skip empty or shell-complex expressions we can't resolve statically
        [ -z "$RESOLVED" ] && continue
        echo "$RESOLVED" | grep -qE '[$`]' && { warn "Cannot statically resolve: $RAW"; continue; }

        if [ -f "$RESOLVED" ]; then
            pass "Library exists: $RESOLVED"
        else
            fail "Library MISSING: $RESOLVED  (from: $line)"
        fi
    done <<< "$SOURCE_LINES"
fi

# ── CHECK 4: registered in settings.json ─────────────────────────────────────
title "4. Registration in settings.json"
if [ ! -f "$SETTINGS" ]; then
    warn "settings.json not found at $SETTINGS — skipping registration check"
else
    # Search for basename in the hooks commands
    MATCH=$(python3 - <<PYEOF 2>/dev/null
import json, sys
with open("$SETTINGS") as f:
    d = json.load(f)
hooks = d.get("hooks", {})
results = []
for event, entries in hooks.items():
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            if "$BASENAME" in cmd:
                results.append(f"{event}: {cmd}")
for r in results:
    print(r)
PYEOF
)
    if [ -n "$MATCH" ]; then
        pass "Registered in settings.json:"
        while IFS= read -r m; do info "  $m"; done <<< "$MATCH"
    else
        warn "NOT found in settings.json (hook may be called indirectly or not yet registered)"
    fi
fi

# ── CHECK 5: executable bit ──────────────────────────────────────────────────
title "5. Executable Bit"
if [ -x "$ABS_PATH" ]; then
    pass "File is executable"
else
    warn "File is NOT executable (settings.json uses 'bash HOOK_FILE' so this may be OK)"
fi

# ── CHECK 6: shellcheck (--full only) ────────────────────────────────────────
if $FULL; then
    title "6. ShellCheck (--full)"
    if command -v shellcheck &>/dev/null; then
        SC_OUT=$(shellcheck -S warning "$ABS_PATH" 2>&1 || true)
        if [ -z "$SC_OUT" ]; then
            pass "ShellCheck: no warnings"
        else
            warn "ShellCheck issues:\n$SC_OUT"
        fi
    else
        warn "shellcheck not installed — skipping"
    fi
fi

# ── Self-syntax check ─────────────────────────────────────────────────────────
# (sanity: this script itself must always pass bash -n)
# Already guaranteed by set -euo pipefail at top

# ── FINAL RESULT ─────────────────────────────────────────────────────────────
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}RESULT: PASS${NC} — $BASENAME looks good"
    exit 0
else
    echo -e "${RED}${BOLD}RESULT: FAIL${NC} — $FAILURES check(s) failed for $BASENAME"
    exit 1
fi
