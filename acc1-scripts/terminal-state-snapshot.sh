#!/bin/bash
# terminal-state-snapshot.sh — Save terminal/server state to Redis
# Run via PM2 cron every 30 min
set +e

# Collect state
PM2_STATE=$(pm2 jlist 2>/dev/null | python3 -c "
import sys, json
try:
    procs = json.load(sys.stdin)
    for p in procs:
        name = p.get('name','?')
        status = p.get('pm2_env',{}).get('status','?')
        pid = p.get('pid',0)
        print(f'{p.get(\"pm_id\",\"?\")}:{name}:{status}:{pid}')
except:
    pass
" 2>/dev/null)

DOCKER_STATE=$(docker ps --format '{{.Names}}:{{.Status}}:{{.Ports}}' 2>/dev/null | head -20)

PROJECT_DIRS=$(ls -d /root/claude-projects/*/ 2>/dev/null | xargs -I{} basename {} | sort | tr '\n' ',')

DISK_STATE=$(df -h /root --output=used,avail,pcent 2>/dev/null | tail -1 | tr -s ' ')

# Build snapshot
SNAPSHOT="PM2:${PM2_STATE}
DOCKER:${DOCKER_STATE}
PROJECTS:${PROJECT_DIRS}
DISK:${DISK_STATE}
TS:$(date -Iseconds)"

# Save to Redis (TTL 1800 = 30 min)
redis-cli SET "terminal:state" "$SNAPSHOT" EX 1800 >/dev/null 2>&1

echo "Terminal state saved to Redis (TTL 30min)"
