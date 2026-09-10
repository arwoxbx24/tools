#!/bin/bash
# Code Statistics Report Generator
# Shows lines of code written by each agent

REDIS_DB=4
TODAY=$(date +%Y-%m-%d)
REPORT_DAYS="${1:-7}"  # Default: last 7 days

echo "═══════════════════════════════════════════════════"
echo "📊 CODE STATISTICS REPORT"
echo "═══════════════════════════════════════════════════"
echo ""

# Today's stats
echo "📅 TODAY ($TODAY)"
echo "───────────────────────────────────────────────────"
printf "%-10s │ %8s │ %8s │ %6s │ %7s\n" "Agent" "Added" "Deleted" "Files" "Commits"
echo "───────────────────────────────────────────────────"

for agent in opus sonnet haiku unknown; do
  ADDED=$(redis-cli -n $REDIS_DB HGET "code:$agent:$TODAY" lines_added 2>/dev/null)
  DELETED=$(redis-cli -n $REDIS_DB HGET "code:$agent:$TODAY" lines_deleted 2>/dev/null)
  FILES=$(redis-cli -n $REDIS_DB HGET "code:$agent:$TODAY" files_changed 2>/dev/null)
  COMMITS=$(redis-cli -n $REDIS_DB HGET "code:$agent:$TODAY" commits 2>/dev/null)

  # Only show if has data
  if [ "${COMMITS:-0}" -gt 0 ]; then
    printf "%-10s │ %+8s │ %8s │ %6s │ %7s\n" \
      "$agent" "+${ADDED:-0}" "-${DELETED:-0}" "${FILES:-0}" "${COMMITS:-0}"
  fi
done

echo ""
echo "📆 LAST $REPORT_DAYS DAYS SUMMARY"
echo "───────────────────────────────────────────────────"
printf "%-10s │ %8s │ %8s │ %7s\n" "Agent" "Added" "Deleted" "Commits"
echo "───────────────────────────────────────────────────"

for agent in opus sonnet haiku unknown; do
  TOTAL_ADDED=0
  TOTAL_DELETED=0
  TOTAL_COMMITS=0

  for i in $(seq 0 $((REPORT_DAYS-1))); do
    DATE=$(date -d "$TODAY - $i days" +%Y-%m-%d 2>/dev/null || date -v-${i}d +%Y-%m-%d)
    ADDED=$(redis-cli -n $REDIS_DB HGET "code:$agent:$DATE" lines_added 2>/dev/null)
    DELETED=$(redis-cli -n $REDIS_DB HGET "code:$agent:$DATE" lines_deleted 2>/dev/null)
    COMMITS=$(redis-cli -n $REDIS_DB HGET "code:$agent:$DATE" commits 2>/dev/null)

    TOTAL_ADDED=$((TOTAL_ADDED + ${ADDED:-0}))
    TOTAL_DELETED=$((TOTAL_DELETED + ${DELETED:-0}))
    TOTAL_COMMITS=$((TOTAL_COMMITS + ${COMMITS:-0}))
  done

  if [ "$TOTAL_COMMITS" -gt 0 ]; then
    printf "%-10s │ %+8s │ %8s │ %7s\n" \
      "$agent" "+$TOTAL_ADDED" "-$TOTAL_DELETED" "$TOTAL_COMMITS"
  fi
done

echo "═══════════════════════════════════════════════════"
echo "Generated: $(date '+%Y-%m-%d %H:%M:%S')"
