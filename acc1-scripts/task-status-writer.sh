#!/bin/bash
# task-status-writer.sh — writes TaskCreate/TaskUpdate events to Redis + /tmp file
# Called by hooks with JSON on stdin
# Usage: echo '{"type":"TaskCreate","input":{"id":"t1","subject":"Fix bug","status":"pending"}}' | bash task-status-writer.sh

set -euo pipefail

REDIS_CLI="${REDIS_CLI:-redis-cli}"
TTL=3600

# Read stdin
INPUT=$(cat)

# Extract fields via jq (exit silently if not a task event)
TASK_ID=$(echo "$INPUT" | jq -r '
  .input.id // .input.task_id // empty
' 2>/dev/null) || true

SUBJECT=$(echo "$INPUT" | jq -r '
  .input.subject // .input.title // empty
' 2>/dev/null) || true

STATUS=$(echo "$INPUT" | jq -r '
  .input.status // "pending"
' 2>/dev/null) || true

# Nothing to do if no task id
[[ -z "$TASK_ID" ]] && exit 0

# Normalize status to known values
case "$STATUS" in
  completed|done)        STATUS="completed" ;;
  in_progress|in-progress|active) STATUS="in_progress" ;;
  *)                     STATUS="pending" ;;
esac

# Determine session id: prefer CLAUDE_SESSION_ID env, fallback to tty/pid
SESSION_ID="${CLAUDE_SESSION_ID:-$(cat /tmp/.claude-session-id 2>/dev/null || echo "default")}"

UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Redis write (idempotent: SETEX overwrites same key) ---
TASK_KEY="task:status:${SESSION_ID}:${TASK_ID}"
TASK_JSON=$(jq -cn \
  --arg subject "$SUBJECT" \
  --arg status "$STATUS" \
  --arg updated_at "$UPDATED_AT" \
  '{"subject":$subject,"status":$status,"updated_at":$updated_at}')

if $REDIS_CLI SET "$TASK_KEY" "$TASK_JSON" EX "$TTL" >/dev/null 2>&1; then
  REDIS_OK=1
else
  REDIS_OK=0
fi

# --- Build summary from all task keys for this session ---
build_summary() {
  local completed=0 in_progress=0 pending=0

  if [[ "$REDIS_OK" -eq 1 ]]; then
    # Scan all task:status keys for this session
    local keys
    keys=$($REDIS_CLI KEYS "task:status:${SESSION_ID}:*" 2>/dev/null) || keys=""

    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      local val
      val=$($REDIS_CLI GET "$key" 2>/dev/null) || continue
      local st
      st=$(echo "$val" | jq -r '.status // "pending"' 2>/dev/null) || continue
      case "$st" in
        completed)  ((completed++))  ;;
        in_progress) ((in_progress++)) ;;
        *)           ((pending++))    ;;
      esac
    done <<< "$keys"
  else
    # Fallback: read from tmp file if exists
    local tmp_file="/tmp/.task-summary-${SESSION_ID}"
    if [[ -f "$tmp_file" ]]; then
      local line
      line=$(cat "$tmp_file")
      # Parse existing summary to extract counts (best-effort)
      completed=$(echo "$line" | grep -oP '✅\K[0-9]+' || echo 0)
      in_progress=$(echo "$line" | grep -oP '⏳\K[0-9]+' || echo 0)
      pending=$(echo "$line" | grep -oP '⬚\K[0-9]+' || echo 0)
      # Update the counter for current status change
      return
    fi
  fi

  local summary=""
  [[ "$completed" -gt 0 ]]   && summary+="✅${completed} "
  [[ "$in_progress" -gt 0 ]] && summary+="⏳${in_progress} "
  [[ "$pending" -gt 0 ]]     && summary+="⬚${pending} "
  summary="${summary% }"  # trim trailing space

  echo "$summary"
}

SUMMARY=$(build_summary)

# Write summary to Redis
if [[ "$REDIS_OK" -eq 1 ]]; then
  $REDIS_CLI SET "task:summary:${SESSION_ID}" "$SUMMARY" EX "$TTL" >/dev/null 2>&1 || true
fi

# Always write to /tmp for tmux fallback
TMP_FILE="/tmp/.task-summary-${SESSION_ID}"
printf '%s' "$SUMMARY" > "$TMP_FILE"

exit 0
