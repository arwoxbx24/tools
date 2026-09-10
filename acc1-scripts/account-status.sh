#!/bin/bash
# Show status of both Claude accounts
# Usage: bash account-status.sh

echo "========================================"
echo "  CLAUDE ACCOUNTS STATUS"
echo "  $(date)"
echo "========================================"
echo ""

echo "📊 Account 1: EXPERT (Primary/Parent)"
echo "   Config: /root/workspaces/tools/acc1-scripts"
echo "   Email: expert.f1h0@gmail.com"
echo "   Subscription: max (5x rate limit)"
EXPERT_STARTUPS=$(cat /root/workspaces/tools/acc1-scripts/.claude.json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('numProfileStartups', 'N/A'))" 2>/dev/null || echo "N/A")
echo "   Startups: $EXPERT_STARTUPS"
echo ""

echo "📊 Account 2: ALEX (Secondary/Child)"
echo "   Config: /root/.claude_alex_acc2"
echo "   Email: alexguzmenko@gmail.com"
echo "   Subscription: pro"
ALEX_STARTUPS=$(cat /root/.claude_alex_acc2/.claude.json 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin).get('numProfileStartups', 'N/A'))" 2>/dev/null || echo "N/A")
echo "   Startups: $ALEX_STARTUPS"
echo ""

echo "📋 Last Delegation:"
if [ -f /root/workspaces/tools/acc1-scripts/data/delegation-status.json ]; then
    cat /root/workspaces/tools/acc1-scripts/data/delegation-status.json
else
    echo "   No delegations yet"
fi
echo ""

echo "📋 Recent Delegation Log:"
if [ -f /root/workspaces/tools/acc1-scripts/logs/delegation.log ]; then
    tail -5 /root/workspaces/tools/acc1-scripts/logs/delegation.log
else
    echo "   No log entries"
fi
echo ""

echo "📋 Last Sync:"
if [ -f /root/workspaces/tools/acc1-scripts/logs/sync-rules.log ]; then
    tail -3 /root/workspaces/tools/acc1-scripts/logs/sync-rules.log
else
    echo "   No sync log"
fi
echo ""
echo "========================================"
