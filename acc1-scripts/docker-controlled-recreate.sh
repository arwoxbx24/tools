#!/usr/bin/env bash
# Controlled Docker container recreate with safety checks
# Usage: docker-controlled-recreate.sh <service_name> <reason> [compose_file]
# Analog of pm2-controlled-restart.sh but for Docker
set -euo pipefail

SERVICE="$1"
REASON="${2:-no reason given}"
COMPOSE_FILE="${3:-docker-compose.yml}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/root/workspaces/tools/acc1-scripts/backups/docker"

echo "=== Docker Controlled Recreate ==="
echo "Service: $SERVICE"
echo "Reason: $REASON"
echo "Timestamp: $TIMESTAMP"

# Step 1: Backup current state
mkdir -p "$BACKUP_DIR"
docker inspect "$SERVICE" > "$BACKUP_DIR/${SERVICE}_${TIMESTAMP}.json" 2>/dev/null || true
echo "[1/4] Backup saved: ${BACKUP_DIR}/${SERVICE}_${TIMESTAMP}.json"

# Step 2: Recreate (down + up for single service)
echo "[2/4] Recreating $SERVICE..."
if [ -f "$COMPOSE_FILE" ]; then
    docker-compose -f "$COMPOSE_FILE" up -d --build --no-deps "$SERVICE"
else
    echo "ERROR: $COMPOSE_FILE not found. Cannot recreate without compose file."
    exit 1
fi

# Step 3: Health check (wait 10s, check running)
echo "[3/4] Health check..."
sleep 5
if docker ps --filter "name=$SERVICE" --filter "status=running" -q | grep -q .; then
    echo "[3/4] OK: $SERVICE is running"
else
    echo "[3/4] FAIL: $SERVICE is NOT running! Check logs: docker logs $SERVICE"
    exit 1
fi

# Step 4: Audit log
echo "[4/4] Audit log entry"
echo "$TIMESTAMP | RECREATE | $SERVICE | $REASON | SUCCESS" >> "$BACKUP_DIR/audit.log"
echo "=== Done ==="
