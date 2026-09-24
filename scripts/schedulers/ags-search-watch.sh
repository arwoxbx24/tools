#!/usr/bin/env bash
# ags-search-watch: one-shot watchdog for the agentskill.sh skill search
# (/learn route). Polled by pm2 cron; alerts go to Telegram via TG_BOT_TOKEN/
# TG_CHAT_ID injected by pm2 from pm2-notify.env. Must always exit 0: failures
# become a dated line in the stdout log.
set -uo pipefail

AGS_API_BASE="${AGS_API_BASE:-https://agentskill.sh}"
AGS_STATE_DIR="${AGS_STATE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/state}"

STATE_FILE="$AGS_STATE_DIR/ags-search-watch.state"
ISSUE="repos/agentskill-sh/ags/issues/18"

log() { printf '%s %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S')" "$1" "${2:-}"; }

state_get() { # key -> value or empty
  local key="$1"
  [ -f "$STATE_FILE" ] || return 0
  awk -F= -v k="$key" '$1==k { print $2 }' "$STATE_FILE"
}

state_set() { # key value (insert or update, keeps other keys)
  local key="$1" val="$2" tmp line changed=0
  tmp="${STATE_FILE}.$$"
  : > "$tmp"
  if [ -f "$STATE_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in
        "$key="*) printf '%s=%s\n' "$key" "$val" >> "$tmp"; changed=1 ;;
        "") : ;;
        *) printf '%s\n' "$line" >> "$tmp" ;;
      esac
    done < "$STATE_FILE"
  fi
  [ "$changed" = 1 ] || printf '%s=%s\n' "$key" "$val" >> "$tmp"
  mv -f "$tmp" "$STATE_FILE"
}

notify() { # text -> 0 only when Telegram actually accepted (ok==true)
  local text="$1" msg now out
  msg=$(printf '%s' "$text" | tr -d '"\r\n' | head -c 400)
  if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
    log "telegram skipped"
    return 1
  fi
  now=$(date +%s)
  if out=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\ndata = "chat_id=%s"\ndata-urlencode = "text=%s"\n' \
      "$TG_BOT_TOKEN" "$TG_CHAT_ID" "$msg" | curl -s --max-time 10 -K - 2>&1) && \
     printf '%s' "$out" | jq -e '.ok == true' >/dev/null 2>&1; then
    log "sent $now"
    return 0
  fi
  log "send failed"
  return 1
}

search_ok() { # 0 if both queries 200, non-empty results, and slugs differ
  local q1 q2 code1 code2 s1 s2 n1 n2 slugs1 slugs2
  q1=$(curl -s --max-time 20 -w '\n%{http_code}' "${AGS_API_BASE}/api/agent/search?q=python&limit=5" 2>/dev/null)
  q2=$(curl -s --max-time 20 -w '\n%{http_code}' "${AGS_API_BASE}/api/agent/search?q=telegram&limit=5" 2>/dev/null)
  code1="${q1##*$'\n'}"; code2="${q2##*$'\n'}"
  { [ "$code1" = "200" ] && [ "$code2" = "200" ]; } || return 1
  s1="${q1%$'\n'*}"; s2="${q2%$'\n'*}"
  n1=$(printf '%s' "$s1" | jq -r '.results | length' 2>/dev/null)
  n2=$(printf '%s' "$s2" | jq -r '.results | length' 2>/dev/null)
  { [ "$n1" -gt 0 ] 2>/dev/null && [ "$n2" -gt 0 ] 2>/dev/null; } || return 1
  slugs1=$(printf '%s' "$s1" | jq -r '.results[].slug' 2>/dev/null)
  slugs2=$(printf '%s' "$s2" | jq -r '.results[].slug' 2>/dev/null)
  { [ -n "$slugs1" ] && [ -n "$slugs2" ] && [ "$slugs1" != "$slugs2" ]; } || return 1
  return 0
}

issue_closed() { # 0 only when issue state == closed (gh failure => unknown/false)
  local state
  state=$(gh api "$ISSUE" --jq .state 2>/dev/null)
  [ "$state" = "closed" ]
}

mkdir -p "$AGS_STATE_DIR"

exec 9>"$AGS_STATE_DIR/ags-search-watch.lock"
if ! flock -n 9; then
  log "locked"
  exit 0
fi

if [ "$(state_get done)" = "1" ]; then
  log "done skipped"
  exit 0
fi

ok_streak=$(state_get ok_streak); ok_streak=${ok_streak:-0}
closed_notified=$(state_get closed_notified); closed_notified=${closed_notified:-0}

if search_ok; then
  ok_streak=$((ok_streak + 1))
  log "search ok streak=$ok_streak"
  state_set ok_streak "$ok_streak"
  if [ "$ok_streak" -ge 2 ]; then
    if notify "✅ Поиск навыков agentskill.sh заработал (проверено дважды подряд). /learn снова можно использовать. Чинит агент: вернуть поиск в маршрут навыков."; then
      state_set done 1
    fi
  fi
else
  log "search failed"
  state_set ok_streak 0
  if issue_closed; then
    if [ "$closed_notified" != "1" ]; then
      if notify "⚠️ Автор agentskill.sh закрыл задачу о сломанном поиске, но поиск всё ещё не работает. /learn пока не использовать. Чинит агент: следим дальше."; then
        state_set closed_notified 1
      fi
    else
      log "closed already notified"
    fi
  else
    log "issue unknown or open"
  fi
fi

exit 0
