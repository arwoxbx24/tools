#!/usr/bin/env bash
# forms-gw-guard: one-shot watchdog for the API gateway serving forms.arwox.ru.
# Polled by pm2 cron; must complete within ~60s. Alerts go to Telegram via
# TG_BOT_TOKEN/TG_CHAT_ID injected by pm2 from pm2-notify.env.
set -uo pipefail

export PATH="$PATH:/root/yandex-cloud/bin"

GUARD_GW_ID="${GUARD_GW_ID:-d5dn462s09a9dpofvl2d}"
GUARD_FORMS_URL="${GUARD_FORMS_URL:-https://forms.arwox.ru/}"
GUARD_BALANCE_MIN="${GUARD_BALANCE_MIN:-10}"
GUARD_STATE_DIR="${GUARD_STATE_DIR:-/root/workspaces/tools/scripts/schedulers/state}"
GUARD_DEBOUNCE_SEC="${GUARD_DEBOUNCE_SEC:-21600}"

STATE_FILE="$GUARD_STATE_DIR/state.json"
BODY_FILE="$GUARD_STATE_DIR/forms-gw-guard.body"
failed=0
form_error=0

log() { printf '%s %s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%S')" "$1" "${2:-}" ; }

notify() { # type text
  local type="$1" text="$2" now ts state json out msg
  now=$(date +%s)
  case "$type" in
    gw_resumed) msg="✅ forms.arwox.ru: шлюз форм был остановлен (реапер YC) — поднят сторожем, форма отвечает <$2>." ;;
    gw_failed) msg="🚨 forms.arwox.ru: шлюз форм STOPPED, resume не удался: $2. Проверить биллинг YC." ;;
    form_error) msg="⚠️ forms.arwox.ru отвечает <$2> (шлюз не остановлен). Проверить функцию arwox-lead-form." ;;
    low_balance) msg="💸 Баланс Yandex Cloud $2 ₽ (< $GUARD_BALANCE_MIN). Пополнить, иначе реапер остановит шлюз форм." ;;
    *) msg="${2:-}" ;;
  esac
  state="{}"
  if [ -f "$STATE_FILE" ]; then
    if json=$(cat "$STATE_FILE" 2>/dev/null) && echo "$json" | jq -e . >/dev/null 2>&1; then
      state="$json"
    else
      log "state reset"
      state="{}"
    fi
  fi
  ts=$(echo "$state" | jq -r --arg t "$type" '.[$t] // 0' 2>/dev/null || echo 0)
  ts=${ts:-0}
  if [ "$ts" != 0 ] && [ $((now - ts)) -lt "$GUARD_DEBOUNCE_SEC" ]; then
    log "debounced $type"
    return 0
  fi
  if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then
    log "telegram skipped $type"
    return 0
  fi
  if out=$(printf 'url = "https://api.telegram.org/bot%s/sendMessage"\ndata = "chat_id=%s"\ndata-urlencode = "text=%s"\n' \
      "$TG_BOT_TOKEN" "$TG_CHAT_ID" "$msg" | curl -s --max-time 10 -K - 2>&1) && \
     printf '%s' "$out" | jq -e '.ok == true' >/dev/null 2>&1; then
    echo "$state" | jq --arg t "$type" --argjson n "$now" '.[$t] = $n' > "$STATE_FILE"
    log "sent $type"
  else
    log "send failed $type"
  fi
}

check_form() { # sets code, ssl, stopped
  local out extra
  out=$(curl -s --max-time 10 -o "$BODY_FILE" -w '%{http_code} %{ssl_verify_result}' "$GUARD_FORMS_URL" 2>&1) || true
  set -- $out
  code="${1:-000}"; ssl="${2:-0}"
  stopped=0
  if grep -q "is stopped and cannot be used" "$BODY_FILE" 2>/dev/null; then stopped=1; fi
  if [ "$code" = "000" ]; then
    extra=$(curl -sk --max-time 10 "$GUARD_FORMS_URL" 2>&1) || extra=""
    if printf '%s' "$extra" | grep -q "is stopped and cannot be used"; then stopped=1; fi
  fi
  log "check code=$code ssl=$ssl stopped=$stopped"
}

form_err_code() { # notify form_error when code is 5xx or 000
  if [ "$code" = "000" ] || { [ -n "$code" ] && [ "$code" -ge 500 ] 2>/dev/null; }; then
    notify form_error "$code"
    form_error=1
  fi
}

mkdir -p "$GUARD_STATE_DIR"

for tool in yc jq curl flock awk; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    log "env missing $tool"
    notify gw_failed "нет инструмента $tool"
    exit 2
  fi
done

exec 9>"$GUARD_STATE_DIR/forms-gw-guard.lock"
if ! flock -n 9; then
  log "already running"
  exit 0
fi

check_form
if [ "$stopped" = 1 ]; then
  if out=$(yc serverless api-gateway get "$GUARD_GW_ID" --format json 2>&1); then
    status=$(printf '%s' "$out" | jq -r .status 2>/dev/null)
    if [ "$status" = "STOPPED" ]; then
      if out=$(yc serverless api-gateway resume "$GUARD_GW_ID" 2>&1); then
        log "resume issued"
        sleep 5
        check_form
        if [ "$stopped" = 0 ]; then
          log "resume ok"
          notify gw_resumed "$code"
          form_err_code
        else
          log "resume pending"
          notify gw_failed "resume принят, форма всё ещё stopped"
          failed=1
        fi
      else
        log "resume failed"
        notify gw_failed "$(printf '%s' "$out" | head -c 200)"
        failed=1
      fi
    else
      notify form_error "тело stopped при статусе $status"
      form_error=1
    fi
  else
    log "resume failed"
    notify gw_failed "$(printf '%s' "$out" | head -c 200)"
    failed=1
  fi
elif [ "$ssl" != 0 ]; then
  notify form_error "TLS ssl_verify_result=$ssl"
  form_error=1
else
  form_err_code
fi

IAM=$(yc iam create-token 2>/dev/null)
if [ -z "$IAM" ]; then
  log "balance skipped"
else
  if resp=$(curl -s --max-time 10 -H "Authorization: Bearer $IAM" \
      https://billing.api.cloud.yandex.net/billing/v1/billingAccounts 2>&1); then
    active=$(printf '%s' "$resp" | jq -r '.billingAccounts[0].active' 2>/dev/null)
    balance=$(printf '%s' "$resp" | jq -r '.billingAccounts[0].balance' 2>/dev/null)
    log "balance $balance active=$active"
    if [ "$active" = "true" ] && awk -v b="$balance" -v m="$GUARD_BALANCE_MIN" 'BEGIN{exit !(b+0<m+0)}'; then
      notify low_balance "$balance"
    fi
  fi
fi

if [ -n "${TG_BOT_TOKEN:-}" ]; then
  user="unknown"
  if out=$(printf 'url = "https://api.telegram.org/bot%s/getMe"\n' "$TG_BOT_TOKEN" | curl -s --max-time 10 -K - 2>&1); then
    user=$(printf '%s' "$out" | jq -r '.result.username' 2>/dev/null)
  fi
  log "bot ${user:-unknown}"
fi

if [ "$failed" = 1 ] || [ "$form_error" = 1 ]; then exit 1; fi
exit 0
