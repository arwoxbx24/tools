#!/usr/bin/env bash
# Догоняет пропущенный ежедневный бэкап после простоя.
set -u

LAST_OK=/root/workspaces/system/tools/scripts/data/server-backup.last-ok
ALERT_PENDING=/root/workspaces/system/tools/scripts/data/server-backup.alert-pending
NOTIFY_ENV=/root/workspaces/projects/hh-scoring/data/notify.env
LOG=/root/workspaces/system/tools/scripts/logs/backup-catchup.log
MAX_AGE=93600
PM2=$(command -v pm2 || echo /usr/local/bin/pm2)

mkdir -p "$(dirname "$LOG")"
if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt $((1024 * 1024)) ]; then
  mv -f "$LOG" "$LOG.1"
fi
log() { echo "[$(date '+%F %T')] $*" >>"$LOG"; }

if [ -f "$ALERT_PENDING" ]; then
  token="" chat=""
  if [ -f "$NOTIFY_ENV" ]; then
    # shellcheck disable=SC1090
    source "$NOTIFY_ENV"
    token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
  fi
  if [ -n "$token" ] && [ -n "$chat" ] \
    && curl -s --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
      -d "chat_id=${chat}" --data-urlencode "text=$(<"$ALERT_PENDING")" >/dev/null 2>&1; then
    rm -f "$ALERT_PENDING"
    log "pending alert sent"
  else
    log "pending alert: сеть недоступна"
  fi
fi

# Нет метки — нужен срочный первый бэкап.
if [ -f "$LAST_OK" ]; then
  age=$(( $(date +%s) - $(cat "$LAST_OK") ))
else
  age=999999999
fi

online=$("$PM2" jlist 2>/dev/null | jq -r '.[] | select(.name=="server-backup") | .pm2_env.status')
if [ "$age" -gt "$MAX_AGE" ]; then
  if [ "$online" = online ]; then
    log "catch-up: server-backup уже выполняется, жду"
    exit 0
  fi
  log "catch-up: last-ok $((age / 3600)) ч назад — запуск server-backup"
  "$PM2" restart server-backup >>"$LOG" 2>&1
  exit 0
fi

log "ok: last-ok $((age / 3600)) ч назад"
exit 0
