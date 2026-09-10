#!/bin/bash
# teamlead-session-init.sh — atomic teamlead session bootstrap
# Restores last session context from Redis + file fallback
set -euo pipefail

SESSION_ID="${CLAUDE_SESSION_ID:-$(redis-cli GET teamlead:current-session 2>/dev/null || echo 'unknown')}"
STATE_DIR="/root/claude-projects/.teamlead-agent/state"
LAST_SESSION_FILE="${STATE_DIR}/last-session.json"

# 1. Restore last session state from Redis
_LAST_PLAN=$(redis-cli HGET "handoff:.teamlead-agent" plan_path 2>/dev/null || echo "")
_LAST_PHASE=$(redis-cli HGET "handoff:.teamlead-agent" phase 2>/dev/null || echo "0")
_LAST_DECISIONS=$(redis-cli LRANGE "teamlead:decisions:recent" 0 4 2>/dev/null || echo "")
_BACKLOG_TOP=$(head -5 "/root/claude-projects/.teamlead-agent/workspace/backlog.md" 2>/dev/null || echo "empty")

# 2. Write last-session.json
cat > "${LAST_SESSION_FILE}" <<EOF
{
  "session_id": "${SESSION_ID}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_plan": "${_LAST_PLAN}",
  "last_phase": "${_LAST_PHASE}",
  "restored_from": "handoff:.teamlead-agent"
}
EOF

# 3. Activate session markers
redis-cli SET "teamlead:current-session" "${SESSION_ID}" EX 28800 &>/dev/null || true
redis-cli SET "teamlead:session:${SESSION_ID}" "active" EX 28800 &>/dev/null || true

# 4. Print context summary
echo "=== TEAMLEAD SESSION INIT ==="
echo "Session: ${SESSION_ID}"
[ -n "$_LAST_PLAN" ] && echo "RESTORE: Last plan: ${_LAST_PLAN} (phase ${_LAST_PHASE})"
[ -n "$_LAST_DECISIONS" ] && echo "RESTORE: Recent decisions:" && echo "$_LAST_DECISIONS"
echo "BACKLOG TOP:" && echo "$_BACKLOG_TOP"
echo "=== READY ==="
