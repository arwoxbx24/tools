#!/bin/bash
SECRETS_OR="/root/workspaces/secrets/services/openrouter.env"
if [[ -f "$SECRETS_OR" ]]; then set -a; source "$SECRETS_OR"; set +a; fi
[ -z "${OPENROUTER_API_KEY:-}" ] && exit 0
RESP=$(curl -s -m 20 -H "Authorization: Bearer $OPENROUTER_API_KEY" https://openrouter.ai/api/v1/auth/key 2>/dev/null)
# fail-closed: on API failure/invalid JSON keep previous level, do not overwrite with GREEN
USAGE=$(jq -er '.data.usage_daily // .data.usage' <<<"$RESP" 2>/dev/null) || exit 0
# цель владельца 24.08: $1/день мягко, перелёт до ~1.3 допустим, полной остановки нет; BLACK=аварийный тормоз 2x
LIMIT="${OR_DAILY_TARGET:-1.0}"
LEVEL=$(awk -v u="$USAGE" -v l="$LIMIT" 'BEGIN {p=u/l; if(p<0.7) print "GREEN"; else if(p<1.0) print "YELLOW"; else if(p<2.0) print "RED"; else print "BLACK"}')
printf '%s\n' "$LEVEL" > /root/workspaces/tools/llm-providers/.or-budget-level
printf '{"ts":"%s","level":"%s","usage":%.4f}\n' "$(date -Iseconds)" "$LEVEL" "$USAGE" >> /root/workspaces/tools/llm-providers/usage.jsonl
exit 0
