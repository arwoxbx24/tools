#!/usr/bin/env bash
set -euo pipefail

DNS_FQDN=${DNS_FQDN:-forms.arwox.ru}
DNS_GW_CNAME=${DNS_GW_CNAME:-d5dn462s09a9dpofvl2d.6brbn2wz.apigw.yandexcloud.net}
BEGET_IP=${BEGET_IP:-}
BEGET_API=${BEGET_API:-https://api.beget.com/api}
GUARD_STATE_DIR=${GUARD_STATE_DIR:-/root/workspaces/tools/scripts/schedulers/state}
BEGET_ENV_FILE=${BEGET_ENV_FILE:-/root/workspaces/secrets/projects/beget.env}
log() { printf '%s forms-dns-switch: %s\n' "$(date -Is)" "$*" >&2; }

usage() { log 'usage: status|apply normal|outage [--fqdn fqdn]'; exit 1; }
case ${1:-} in
  status) action=status; shift ;;
  apply) action=apply; target=${2:-}; [ "$target" = normal ] || [ "$target" = outage ] || usage; shift 2 ;;
  *) usage ;;
esac
if [ "${1:-}" = --fqdn ]; then DNS_FQDN=${2:-}; [ -n "$DNS_FQDN" ] || usage; shift 2; fi
[ "$#" = 0 ] || usage
if { [ -z "${BEGET_LOGIN:-}" ] || [ -z "${BEGET_API_PASSWORD:-}" ]; } && [ -f "$BEGET_ENV_FILE" ]; then . "$BEGET_ENV_FILE"; fi
mkdir -p "$GUARD_STATE_DIR"
STATE="$GUARD_STATE_DIR/forms-dns.$DNS_FQDN.json"
SNAPSHOT="$GUARD_STATE_DIR/forms-dns.snapshot.$DNS_FQDN.json"
exec 9>"$GUARD_STATE_DIR/forms-dns.$DNS_FQDN.lock"
if ! flock -n 9; then printf 'api_error locked\n'; exit 2; fi
state=$(jq -c . "$STATE" 2>/dev/null || printf '%s' '{"api_fail":0,"notified":{}}')
save() { printf '%s\n' "$state" > "$STATE"; }
notify() {
  local type=$1 text=$2 now last
  if [ -z "${TG_BOT_TOKEN:-}" ] || [ -z "${TG_CHAT_ID:-}" ]; then log "notify skipped $type"; return; fi
  now=$(date +%s); last=$(jq -r --arg type "$type" '.notified[$type] // 0' <<< "$state")
  if [ $((now - last)) -lt 21600 ]; then log "debounced $type"; return; fi
  # ponytail: notify повторяет сторож; общий файл при третьем потребителе.
  printf 'url = "https://api.telegram.org/bot%s/sendMessage"\ndata-urlencode = "chat_id=%s"\ndata-urlencode = "text=%s"\n' "$TG_BOT_TOKEN" "$TG_CHAT_ID" "$text" | curl -s --max-time 10 -K - >/dev/null || log "notify failed $type"
  state=$(jq --arg type "$type" --argjson now "$now" '.notified[$type]=$now' <<< "$state"); save
}
reset_api() { state=$(jq '.api_fail=0' <<< "$state"); save; }
beget() {
  local reply input=${2//\"/\\\"}
  if ! reply=$(printf 'url = "%s/%s"\ndata-urlencode = "login=%s"\ndata-urlencode = "passwd=%s"\ndata-urlencode = "input_format=json"\ndata-urlencode = "output_format=json"\ndata-urlencode = "input_data=%s"\n' "$BEGET_API" "$1" "${BEGET_LOGIN:-}" "${BEGET_API_PASSWORD:-}" "$input" | curl -s --max-time 15 -K -); then BEGET_ERROR=NET; return 1; fi
  if jq -e '.status == "success" and .answer.status == "success"' <<< "$reply" >/dev/null 2>&1; then BEGET_RESULT=$(jq -c '.answer.result' <<< "$reply"); reset_api; return; fi
  BEGET_ERROR=$(jq -r '.error_code // .answer.errors[0].error_code // "NET"' <<< "$reply" 2>/dev/null || printf NET); return 1
}
api_error() {
  state=$(jq '.api_fail=(.api_fail // 0)+1' <<< "$state"); save
  [ "$(jq -r '.api_fail' <<< "$state")" = 3 ] && notify api_fail "forms DNS API error: $BEGET_ERROR"
  printf 'api_error %s\n' "$BEGET_ERROR"; exit 2
}
load_mode() {
  beget dns/getData "$(jq -cn --arg fqdn "$DNS_FQDN" '{fqdn:$fqdn}')" || return 1
  DNS_DATA=$BEGET_RESULT
  if jq -e --arg cname "$DNS_GW_CNAME" '(.records.CNAME // []) as $c | (.records.A // []) as $a | ($c|length)==1 and ($a|length)==0 and ($c[0].value|sub("\\.$"; "")) == $cname' <<< "$DNS_DATA" >/dev/null; then MODE=normal
  elif jq -e --arg ip "$BEGET_IP" '(.records.CNAME // []) as $c | (.records.A // []) as $a | ($a|length)==1 and ($c|length)==0 and $ip != "" and $a[0].value == $ip' <<< "$DNS_DATA" >/dev/null; then MODE=outage
  else MODE=foreign; fi
}
load_mode || api_error
current=$MODE
if [ "$action" = status ]; then printf '%s\n' "$current"; [ "$current" != foreign ] || exit 4; exit 0; fi
if [ "$current" = foreign ]; then notify foreign "forms DNS is foreign: $DNS_FQDN"; printf 'foreign\n'; exit 4; fi
if [ "$current" = "$target" ]; then printf 'noop %s\n' "$target"; exit 0; fi
[ "$target" != outage ] || [ -n "$BEGET_IP" ] || { notify refused "forms DNS no BEGET_IP"; printf 'refused precheck no BEGET_IP\n'; exit 3; }
[ -e "$SNAPSHOT" ] || printf '%s\n' "$DNS_DATA" > "$SNAPSHOT"
if [ "$target" = outage ]; then
  header=$(curl -sI --max-time 10 --resolve "$DNS_FQDN:443:$BEGET_IP" "https://$DNS_FQDN/" || true)
  code=$(awk 'NR == 1 { print $2; exit }' <<< "$header")
  if [ "$code" != 302 ] || ! grep -qi '^location:[[:space:]]*https://arwox.ru/#contact[[:space:]]*$' <<< "$header"; then notify refused "forms DNS precheck: ${code:-NET}"; printf 'refused precheck %s\n' "${code:-NET}"; exit 3; fi
  records=$(jq -cn --arg ip "$BEGET_IP" '{A:[{priority:10,value:$ip}]}')
else
  records=$(jq -cn --arg cname "$DNS_GW_CNAME" '{CNAME:[{priority:10,value:$cname}]}')
fi
beget dns/changeRecords "$(jq -cn --arg fqdn "$DNS_FQDN" --argjson records "$records" '{fqdn:$fqdn,records:$records}')" >/dev/null || api_error
load_mode || api_error
verified=$MODE
if [ "$verified" != "$target" ]; then printf 'api_error verify\n'; exit 2; fi
printf 'switched %s→%s\n' "$current" "$target"
