#!/bin/bash
# ACS - Agent Compliance System - Report Generator

REDIS_DB=2
PERIOD=${1:-7d}
AGENT=${2:-all}

echo "═══════════════════════════════════════════"
echo "   ACS COMPLIANCE REPORT"
echo "   Period: $PERIOD | Agent: $AGENT"
echo "═══════════════════════════════════════════"
echo ""

# Violations summary
echo "📊 VIOLATIONS BY RULE:"
echo "───────────────────────────────────────────"
for rule in DRFIT PROGRESS FIXATION VERIFICATION VALIDATION; do
  count=$(redis-cli -n $REDIS_DB GET "acs:stats:rule:$rule" 2>/dev/null || echo "0")
  printf "  %-15s %s\n" "$rule:" "${count:-0}"
done

echo ""
echo "👤 AGENT STATS:"
echo "───────────────────────────────────────────"
for agent in opus sonnet haiku; do
  if [[ "$AGENT" == "all" || "$AGENT" == "$agent" ]]; then
    score=$(redis-cli -n $REDIS_DB HGET "acs:stats:agent:$agent" "compliance_score" 2>/dev/null || echo "100")
    violations=$(redis-cli -n $REDIS_DB HGET "acs:stats:agent:$agent" "violations" 2>/dev/null || echo "0")
    printf "  %-10s Score: %3s%% | Violations: %s\n" "$agent:" "${score:-100}" "${violations:-0}"
  fi
done

echo ""
echo "📋 RECENT VIOLATIONS (last 10):"
echo "───────────────────────────────────────────"
TODAY=$(date +%Y-%m-%d)
redis-cli -n $REDIS_DB LRANGE "acs:violations:$TODAY" -10 -1 2>/dev/null | while read line; do
  echo "  $line"
done

echo ""
echo "═══════════════════════════════════════════"
