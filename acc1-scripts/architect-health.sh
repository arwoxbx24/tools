#!/bin/bash
# architect-health.sh — Architect-First Compliance Dashboard
set +e

GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'
BOLD='\033[1m'; RESET='\033[0m'

redis-cli PING >/dev/null 2>&1 || { echo "ERROR: Redis unavailable"; exit 1; }

TODAY=$(date +%Y%m%d)
NOW=$(date '+%Y-%m-%d %H:%M')

# Lifetime
COMPLETED=$(redis-cli GET "architect:completed:total" 2>/dev/null); COMPLETED=${COMPLETED:-0}
SKIPPED=$(redis-cli GET "architect:skipped:total" 2>/dev/null); SKIPPED=${SKIPPED:-0}
TOTAL=$((COMPLETED + SKIPPED))
[[ $TOTAL -gt 0 ]] && PCT=$((COMPLETED * 100 / TOTAL)) || PCT=100

# Today
OK_T=$(redis-cli GET "architect:ok:${TODAY}" 2>/dev/null); OK_T=${OK_T:-0}
SKIP_T=$(redis-cli GET "architect:skipped:${TODAY}" 2>/dev/null); SKIP_T=${SKIP_T:-0}
BYPASS_T=$(redis-cli GET "architect:bypassed:${TODAY}" 2>/dev/null); BYPASS_T=${BYPASS_T:-0}

# Active sessions
ACTIVE=$(redis-cli KEYS "architect:session:*" 2>/dev/null | wc -l)

# Score color
if [[ $PCT -ge 90 ]]; then C=$GREEN; S="HEALTHY"
elif [[ $PCT -ge 70 ]]; then C=$YELLOW; S="FAIR"
else C=$RED; S="LOW"; fi

echo ""
echo "╔══════════════════════════════════════════════╗"
printf "║  ${BOLD}ARCHITECT-FIRST HEALTH${RESET}        $NOW  ║\n"
echo "╠══════════════════════════════════════════════╣"
printf "║  Compliance: ${C}${PCT}%%${RESET} ($COMPLETED ok / $SKIPPED skip)  ${C}${S}${RESET}\n"
echo "╠══════════════════════════════════════════════╣"
printf "║  Today: ${GREEN}OK=$OK_T${RESET}  ${RED}Skip=$SKIP_T${RESET}  ${YELLOW}Bypass=$BYPASS_T${RESET}\n"
printf "║  Active sessions: $ACTIVE\n"
echo "╠══════════════════════════════════════════════╣"
echo "║  Recent skips:"

SKIP_COUNT=$(redis-cli LLEN "architect:skips:recent" 2>/dev/null); SKIP_COUNT=${SKIP_COUNT:-0}
if [[ $SKIP_COUNT -gt 0 ]]; then
    redis-cli LRANGE "architect:skips:recent" 0 4 2>/dev/null | while IFS= read -r entry; do
        TS=$(echo "$entry" | jq -r '.ts // "?"' 2>/dev/null | cut -c1-16)
        TYPE=$(echo "$entry" | jq -r '.type // "?"' 2>/dev/null)
        printf "║    %-16s  %s\n" "$TS" "$TYPE"
    done
else
    echo "║    None"
fi
echo "╚══════════════════════════════════════════════╝"
