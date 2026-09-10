#!/bin/bash
# Start PM2 Conductor with verification

CONDUCTOR_HOME="/root/workspaces/tools/acc1-scripts"

echo "🎭 Starting PM2 Conductor..."

# 1. Verify dependencies
echo "Checking dependencies..."
which pm2 >/dev/null || { echo "❌ pm2 not found"; exit 1; }
which jq >/dev/null || { echo "❌ jq not found"; exit 1; }
which claude >/dev/null || { echo "❌ claude not found"; exit 1; }
redis-cli ping >/dev/null || { echo "❌ Redis not available"; exit 1; }
echo "✅ All dependencies OK"

# 2. Verify config
[ -f "$CONDUCTOR_HOME/config/error-patterns.json" ] || { echo "❌ error-patterns.json missing"; exit 1; }
[ -f "$CONDUCTOR_HOME/config/pm2-conductor.json" ] || { echo "❌ pm2-conductor.json missing"; exit 1; }
echo "✅ Config files OK"

# 3. Initialize Redis
redis-cli -n 3 SET "conductor:version" "1.0" >/dev/null
redis-cli -n 3 SET "conductor:initialized" "$(date -Iseconds)" >/dev/null
echo "✅ Redis initialized"

# 4. Start conductor
pm2 start "$CONDUCTOR_HOME/config/pm2-conductor.json"

# 5. Verify running
sleep 2
if pm2 list | grep -q "pm2-conductor.*online"; then
  echo "✅ PM2 Conductor is running"
  pm2 logs pm2-conductor --lines 5 --nostream
else
  echo "❌ Conductor failed to start"
  pm2 logs pm2-conductor --err --lines 20 --nostream
  exit 1
fi

echo ""
echo "🎭 Conductor is now monitoring all PM2 processes"
echo "   View logs: pm2 logs pm2-conductor"
echo "   Check state: cat $CONDUCTOR_HOME/data/conductor-state.json"
