#!/bin/bash
# validate-pm2-health.sh
# Checks that critical PM2 services are running
# Returns: exit 0 if all online, exit 1 if any stopped/errored

# Critical services that MUST be running
CRITICAL_SERVICES=(
    "sched-healthcheck"
    "sched-clean-disk"
    "sched-clear-ram"
    "session-indexer"
    "memory-updater"
    "context-gc"
    "context-heartbeat"
    "session-merger"
)

ERRORS=()

# Get PM2 status
PM2_STATUS=$(pm2 jlist 2>/dev/null)

if [ -z "$PM2_STATUS" ] || [ "$PM2_STATUS" = "[]" ]; then
    echo "PM2 not running or no processes"
    exit 1
fi

for service in "${CRITICAL_SERVICES[@]}"; do
    STATUS=$(echo "$PM2_STATUS" | jq -r ".[] | select(.name == \"$service\") | .pm2_env.status" 2>/dev/null)

    if [ -z "$STATUS" ]; then
        ERRORS+=("$service:missing")
    elif [ "$STATUS" != "online" ]; then
        ERRORS+=("$service:$STATUS")
    fi
done

if [ ${#ERRORS[@]} -eq 0 ]; then
    echo "All critical PM2 services online"
    exit 0
else
    echo "PM2 issues: ${ERRORS[*]}"
    exit 1
fi
