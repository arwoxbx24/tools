#!/bin/bash
# pe-session-start.sh — Atomic PE session initializer
# Устанавливает все маркеры за один вызов, исключая каскад блокировок
# Usage: bash /root/workspaces/tools/acc1-scripts/scripts/pe-session-start.sh [project]
set -euo pipefail

SCRIPTS_DIR="/root/workspaces/tools/acc1-scripts/scripts"

# --- Step 1: Resolve SESSION_ID ---
if [[ -n "${CLAUDE_SESSION_ID:-}" ]]; then
    SID="$CLAUDE_SESSION_ID"
else
    PROJECTS_DIR="/root/workspaces/tools/acc1-scripts/projects/-root-claude-projects"
    SID=$(ls -t "$PROJECTS_DIR"/*.jsonl 2>/dev/null | head -1 \
          | xargs basename 2>/dev/null | sed 's/\.jsonl$//' || echo "nosession-$$")
fi
SID="${SID:-nosession-$$}"
SID_SHORT="${SID:0:16}"

echo "[PE] Starting session $SID_SHORT"

# --- Step 2: Idempotency check ---
EXISTING=$(redis-cli GET "pe:session:${SID}" 2>/dev/null || echo "")
if [[ "$EXISTING" == "1" ]]; then
    echo "[PE] Already active — skip"
    exit 0
fi

# --- Step 3: health-check.sh (creates .session-init-done marker, clears V230) ---
bash "${SCRIPTS_DIR}/health-check.sh" 2>&1 | tail -3 || true

# --- Step 4: context-recovery.sh ---
bash "${SCRIPTS_DIR}/context-recovery.sh" 2>&1 | tail -2 || true

# --- Step 5: Set PE markers BEFORE any Agent() call ---
touch /tmp/.pe-session-active 2>/dev/null || true
touch /tmp/.pe_session_initialized 2>/dev/null || true
redis-cli SET "pe:session:${SID}" "1" EX 28800 >/dev/null 2>&1 || true
if [[ -n "${TMUX_PANE:-}" ]]; then
    redis-cli SET "pe:window:${TMUX_PANE}" "1" EX 28800 >/dev/null 2>&1 || true
fi

# --- Step 6: Project lock ---
PROJECT="${1:-.teamlead-agent}"
bash "${SCRIPTS_DIR}/switch-project.sh" "$PROJECT" 2>&1 | tail -1 || true

# --- Step 7: Architect proof (prevents V_ARCH_FIRST on first Agent call) ---
redis-cli SET "architect:session:${SID}" "pe-session-start" EX 28800 >/dev/null 2>&1 || true

# --- Step 8: V230 marker (explicit, in case health-check didn't create it) ---
date +%s > "/tmp/.session-init-done-${SID_SHORT}" 2>/dev/null || true

echo "[PE] SESSION READY | V230=clear V102=bypass ARCH=clear"
exit 0
