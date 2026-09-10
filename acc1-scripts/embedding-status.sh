#!/bin/bash
# Embedding Provider Status - быстрая диагностика
# Run: bash /root/workspaces/tools/acc1-scripts/scripts/embedding-status.sh

LOG_FILE="/root/workspaces/tools/acc1-scripts/logs/embeddings.log"

echo "========================================"
echo "  EMBEDDING PROVIDERS STATUS"
echo "  $(date)"
echo "========================================"
echo ""

if [ ! -f "$LOG_FILE" ]; then
    echo "⚠️  No log file found. No embeddings generated yet."
    exit 0
fi

echo "📊 Last 24 hours summary:"
echo ""

# Count by provider and status
echo "Provider      | Success | Failed  | Last Event"
echo "------------- | ------- | ------- | -----------"

for provider in VOYAGE JINA OPENAI LOCAL; do
    success=$(grep "$provider.*SUCCESS" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
    failed=$(grep -E "$provider.*(FAILED|FALLBACK)" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
    last=$(grep "$provider" "$LOG_FILE" 2>/dev/null | tail -1 | cut -d'|' -f2 | xargs)
    printf "%-13s | %7s | %7s | %s\n" "$provider" "$success" "$failed" "${last:-never}"
done

echo ""
echo "📋 Last 10 events:"
echo ""
tail -10 "$LOG_FILE"

echo ""
echo "========================================"

# Alert if issues detected
if grep -q "LOCAL.*FALLBACK" "$LOG_FILE" 2>/dev/null; then
    echo ""
    echo "⚠️  WARNING: Local fallback was used!"
    echo "   All remote providers failed at some point."
    echo "   Check the log for details."
fi

voyage_failures=$(grep "VOYAGE.*FAILED" "$LOG_FILE" 2>/dev/null | wc -l | tr -d ' ')
if [ "$voyage_failures" -gt 5 ]; then
    echo ""
    echo "🔴 ALERT: Voyage AI has multiple failures!"
    echo "   Check Cloudflare Worker status."
    echo "   Errors:"
    grep "VOYAGE.*FAILED" "$LOG_FILE" | tail -3
fi
