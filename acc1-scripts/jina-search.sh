#!/bin/bash
# Jina AI Semantic Search
# Usage: jina-search.sh "query" [--rerank] [--top=N]
# Free tier: 1M tokens/month

set -e

QUERY="$1"
RERANK=""
TOP="5"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --rerank) RERANK="true" ;;
    --top=*) TOP="${arg#*=}" ;;
  esac
done

# Load API key
JINA_API_KEY="${JINA_API_KEY:-}"
[[ -z "$JINA_API_KEY" ]] && source /root/workspaces/tools/acc1-scripts/config/.env 2>/dev/null || true

if [[ -z "$JINA_API_KEY" ]]; then
  echo "❌ JINA_API_KEY not set"
  echo "Get free key: https://jina.ai/"
  exit 1
fi

if [[ -z "$QUERY" ]]; then
  echo "Usage: jina-search.sh \"query\" [--rerank] [--top=N]"
  exit 1
fi

echo "🔎 Searching: $QUERY"

# Use Jina Reader API for web search
RESPONSE=$(curl -s "https://s.jina.ai/$QUERY" \
  -H "Authorization: Bearer $JINA_API_KEY" \
  -H "Accept: application/json" \
  -H "X-Return-Format: json")

# Check for error
if echo "$RESPONSE" | jq -e '.error' &>/dev/null; then
  echo "❌ Error: $(echo "$RESPONSE" | jq -r '.error')"
  exit 1
fi

# Output results
echo "$RESPONSE" | jq -r ".data[:$TOP][] | \"[\(.title)]\n\(.url)\n\(.description // .content[:200])\n\""
