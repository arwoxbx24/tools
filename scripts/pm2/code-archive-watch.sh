#!/usr/bin/env bash
# code-archive-watch.sh — сторож архива: restart/уведомление при простое last-ok.
set -euo pipefail
CAW_DIR="${CAW_DIR:-/root/workspaces/system/services/gitmirror}"
CAW_PM2="${CAW_PM2:-pm2}"
CAW_NOTIFY="${CAW_NOTIFY:-}"
NOTIFY_ENV=/root/workspaces/secrets/services/pm2-notify.env
LOG="$CAW_DIR/code-archive.log"
LAST_OK="$CAW_DIR/last-ok"
mkdir -p "$CAW_DIR"
if [ -f "$LOG" ] && [ "$(stat -c%s "$LOG")" -gt 1048576 ]; then
  mv -f "$LOG" "$LOG.1"
fi
log() { echo "$(date '+%F_%T') $*" >>"$LOG"; }
if [ -f "$LAST_OK" ]; then
  lok_ts=$(stat -c %Y "$LAST_OK")
  age_h=$(( ($(date +%s) - lok_ts) / 3600 ))
  last_date=$(date -d "@$lok_ts" '+%F %T')
else
  lok_ts=0; age_h=9999; last_date=""
fi
if [ "$age_h" -gt 26 ]; then
  "$CAW_PM2" restart code-archive >>"$LOG" 2>&1
  log "watch: restart (last-ok ${last_date:-нет})"
fi
if [ "$age_h" -gt 48 ]; then
  lastln=$(grep -n '^=== pass' "$LOG" 2>/dev/null | tail -n1 | cut -d: -f1 || true)
  pass_err=0; names=""
  if [ -n "$lastln" ]; then
    line=$(sed -n "${lastln}p" "$LOG")
    pass_err=$(awk '{for(i=1;i<=NF;i++) if($i ~ /^err=/) {split($i,a,"="); print a[2]}}' <<<"$line")
    pt=$(awk '{print $3}' <<<"$line" | tr '_' ' ')
    pe=$(date -d "$pt" '+%s' 2>/dev/null || echo 0)
    if [ "$pe" -gt "$lok_ts" ] && [ "${pass_err:-0}" -gt 0 ]; then
      names=$(sed -n "${lastln},\$p" "$LOG" | grep ' err:' 2>/dev/null | awk '{print $2" "$3}' | tr '\n' ' ' || true)
    fi
  fi
  if [ -n "${names% }" ]; then
    msg="сбой у ${names% }, последний успех ${last_date}"
  else
    msg="проходов не было, последний успех ${last_date:-никогда}"
  fi
  if [ -n "$CAW_NOTIFY" ]; then
    "$CAW_NOTIFY" "$msg"
  else
    token=""; chat=""
    if [ -f "$NOTIFY_ENV" ]; then
      # shellcheck disable=SC1090
      source "$NOTIFY_ENV"
      token="${TG_BOT_TOKEN:-}"; chat="${TG_CHAT_ID:-}"
    fi
    if [ -n "$token" ] && [ -n "$chat" ]; then
      curl -s --max-time 10 "https://api.telegram.org/bot${token}/sendMessage" \
        -d "chat_id=${chat}" --data-urlencode "text=${msg}" >/dev/null 2>&1 || true
    fi
  fi
fi
exit 0
