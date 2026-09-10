#!/bin/bash
# ACS - Log Violation
# Usage: acs-log.sh <agent> <rule_code> <description>
# Example: acs-log.sh sonnet V001 "DRFIT format not used"

REDIS_DB=2
AGENT=${1:-unknown}
RULE=${2:-V000}
DESC=${3:-"No description"}
DATE=$(date +%Y-%m-%d)
TIME=$(date +%H:%M:%S)

# Validate agent
if [[ ! "$AGENT" =~ ^(opus|sonnet|haiku)$ ]]; then
  echo "❌ Invalid agent: $AGENT (must be opus|sonnet|haiku)"
  exit 1
fi

# Log violation
ENTRY="$TIME|$AGENT|$RULE|$DESC"
redis-cli -n $REDIS_DB RPUSH "acs:violations:$DATE" "$ENTRY" > /dev/null
redis-cli -n $REDIS_DB RPUSH "acs:violations:$AGENT:$DATE" "$ENTRY" > /dev/null

# Extract rule name from code (V001 -> DRFIT, etc)
case $RULE in
  V001) RULE_NAME="DRFIT" ;;
  V002) RULE_NAME="PROGRESS" ;;
  V003) RULE_NAME="FIXATION" ;;
  V004) RULE_NAME="VERIFICATION" ;;
  V005) RULE_NAME="VALIDATION" ;;
  V011) RULE_NAME="QUESTION" ;;
  V012) RULE_NAME="GIT" ;;
  *) RULE_NAME="OTHER" ;;
esac

# Increment counters
redis-cli -n $REDIS_DB INCR "acs:stats:rule:$RULE_NAME" > /dev/null
redis-cli -n $REDIS_DB HINCRBY "acs:stats:agent:$AGENT" "violations" 1 > /dev/null

# Recalculate compliance score (simplified)
VIOLATIONS=$(redis-cli -n $REDIS_DB HGET "acs:stats:agent:$AGENT" "violations")
TASKS=$(redis-cli -n $REDIS_DB HGET "acs:stats:agent:$AGENT" "total_tasks")
TASKS=${TASKS:-1}
SCORE=$((100 - (VIOLATIONS * 100 / (TASKS + VIOLATIONS + 1))))
[[ $SCORE -lt 0 ]] && SCORE=0
redis-cli -n $REDIS_DB HSET "acs:stats:agent:$AGENT" "compliance_score" "$SCORE" > /dev/null

echo "⚠️ ACS: Violation logged [$RULE] $AGENT - $DESC"
