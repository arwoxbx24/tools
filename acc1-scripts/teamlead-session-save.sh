#!/bin/bash
# teamlead-session-save.sh — save current session context for next restore
set -euo pipefail

SESSION_ID="${CLAUDE_SESSION_ID:-$(redis-cli GET teamlead:current-session 2>/dev/null || echo 'unknown')}"
STATE_DIR="/root/claude-projects/.teamlead-agent/state"

_ACTIVE_PLAN=$(redis-cli GET "plan:active:${SESSION_ID}" 2>/dev/null || echo "")
_PHASE=$(redis-cli HGET "handoff:.teamlead-agent" phase 2>/dev/null || echo "0")
_NEW_PHASE=$(( _PHASE + 1 ))

redis-cli HSET "handoff:.teamlead-agent" \
  plan_path "${_ACTIVE_PLAN}" \
  phase "${_NEW_PHASE}" \
  session_id "${SESSION_ID}" \
  saved_at "$(date -u +%s)" \
  tier "TEAMLEAD" &>/dev/null || true
redis-cli EXPIRE "handoff:.teamlead-agent" 604800 &>/dev/null || true

# File fallback
cat > "${STATE_DIR}/last-session.json" <<EOF
{
  "session_id": "${SESSION_ID}",
  "saved_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "plan": "${_ACTIVE_PLAN}",
  "phase": "${_NEW_PHASE}"
}
EOF

echo "[teamlead-session-save] Saved. Plan: ${_ACTIVE_PLAN}, Phase: ${_NEW_PHASE}"
