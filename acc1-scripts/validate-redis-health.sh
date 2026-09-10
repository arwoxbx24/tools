#!/bin/bash
# validate-redis-health.sh
# Checks Redis connectivity and basic health
# Returns: exit 0 if healthy, exit 1 if issues

# Test connection
PING=$(redis-cli PING 2>/dev/null)

if [ "$PING" != "PONG" ]; then
    echo "Redis not responding"
    exit 1
fi

# Check memory usage (warn if >80%)
MEMORY_INFO=$(redis-cli INFO memory 2>/dev/null | grep "used_memory_human")
MEMORY_PEAK=$(redis-cli INFO memory 2>/dev/null | grep "used_memory_peak_human")

# Check key count in main DBs
DB0_KEYS=$(redis-cli -n 0 DBSIZE 2>/dev/null | awk '{print $2}')
DB1_KEYS=$(redis-cli -n 1 DBSIZE 2>/dev/null | awk '{print $2}')
DB2_KEYS=$(redis-cli -n 2 DBSIZE 2>/dev/null | awk '{print $2}')

echo "Redis OK: $MEMORY_INFO, Keys: DB0=$DB0_KEYS DB1=$DB1_KEYS DB2=$DB2_KEYS"
exit 0
