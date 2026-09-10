#!/bin/bash
# Voyage AI Embeddings Client
# Usage: voyage-embed.sh "text" [--model=voyage-code-3]
# Free tier: voyage-code-3 optimized for code

set -e

TEXT="$1"
MODEL="voyage-code-3"

# Parse arguments
for arg in "$@"; do
  case $arg in
    --model=*) MODEL="${arg#*=}" ;;
  esac
done

# Load API key (check multiple locations)
VOYAGE_API_KEY="${VOYAGE_API_KEY:-}"
[[ -z "$VOYAGE_API_KEY" ]] && source /root/workspaces/tools/acc1-scripts/config/.env 2>/dev/null || true

if [[ -z "$VOYAGE_API_KEY" ]]; then
  echo "❌ VOYAGE_API_KEY not set"
  echo "Get free key: https://www.voyageai.com/"
  exit 1
fi

if [[ -z "$TEXT" ]]; then
  echo "Usage: voyage-embed.sh \"text\" [--model=voyage-code-3]"
  echo "Models: voyage-code-3, voyage-3, voyage-3-lite"
  exit 1
fi

# Call Voyage API
RESPONSE=$(curl -s https://api.voyageai.com/v1/embeddings \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VOYAGE_API_KEY" \
  -d "{
    \"input\": \"$TEXT\",
    \"model\": \"$MODEL\"
  }")

# Check for error
ERROR=$(echo "$RESPONSE" | jq -r '.error // empty')
if [[ -n "$ERROR" ]]; then
  echo "❌ Error: $ERROR"
  exit 1
fi

# Output embedding (first 10 values + dimension)
DIM=$(echo "$RESPONSE" | jq '.data[0].embedding | length')
PREVIEW=$(echo "$RESPONSE" | jq '.data[0].embedding[0:5]')

echo "✅ Embedding generated"
echo "   Model: $MODEL"
echo "   Dimensions: $DIM"
echo "   Preview: $PREVIEW..."

# Full output to stdout if piped
if [[ ! -t 1 ]]; then
  echo "$RESPONSE" | jq '.data[0].embedding'
fi
